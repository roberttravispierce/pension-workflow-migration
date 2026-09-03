# Stand-in for the PowerCenter Integration Service: parses the workflow XML
# and executes it. The business rules are NOT in this file — they live in the
# XML's expression strings, which this engine evaluates. This file implements
# only engine semantics (port evaluation order, variable persistence, lookup
# policy, sorter, aggregator, joiner, filter), the way the real Integration
# Service does.
#
# All arithmetic is exact (Rational); ROUND is half-up, per Oracle convention.
#
# Usage: ruby legacy/integration_service.rb 2026-09

require "rexml/document"
require "date"
require "json"
require "digest"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
INPUT = File.join(ROOT, "data/input")
GOLDEN = File.join(ROOT, "data/golden")
STAGING = File.join(ROOT, "tmp/legacy")

run_period = ARGV[0] or abort "usage: ruby legacy/integration_service.rb YYYY-MM"
prd = Date.parse("#{run_period}-01")
RUN_PRD_END = Date.new(prd.year, prd.month, -1)

# --- Expression language ----------------------------------------------------

# NULL propagation, SQL-style: arithmetic with NULL yields NULL, comparisons
# with NULL are false. Ruby's nil is our NULL; IIF evaluates both branches
# (as a method call must), so the unused branch has to survive NULL inputs.
class NilClass
  [:+, :-, :*, :/].each { |op| define_method(op) { |_| nil } }
  [:<, :>, :<=, :>=].each { |op| define_method(op) { |_| false } }
end

module PCFunctions
  def iif(cond, a, b) = cond ? a : b
  def isnull(x) = x.nil?

  def decode(value, *pairs)
    default = pairs.length.odd? ? pairs.pop : nil
    pairs.each_slice(2) { |k, v| return v if value == k }
    default
  end

  # Oracle-style: whole-month difference plus (day1 - day2)/31 as fraction.
  def months_between(d1, d2)
    return nil if d1.nil? || d2.nil?
    whole = (d1.year - d2.year) * 12 + (d1.month - d2.month)
    Rational(whole) + Rational(d1.day - d2.day, 31)
  end

  def trunc(x, n) = x.nil? ? nil : Rational((x * 10**n).to_i, 10**n)
  def pc_round(x, n) = x.nil? ? nil : Rational(x).round(n, half: :up)
  def get_date_part(d, part) = d.nil? ? nil : (part.upcase == "YYYY" ? d.year : (raise "unsupported: #{part}"))
end

class ExprContext
  include PCFunctions

  def initialize(params)
    @ports = {}
    @params = params
  end

  def []=(name, value)
    @ports[name.to_s.downcase] = value
  end

  def [](name) = @ports[name.to_s.downcase]
  def to_h = @ports.transform_keys(&:upcase)

  # A port whose evaluation still hits NULL where a number was needed
  # (e.g. NULL on the right of Integer#-) evaluates to NULL, matching the
  # Integration Service's treatment of transformation evaluation errors.
  def evaluate(ruby_expr)
    instance_eval(ruby_expr)
  rescue TypeError, NoMethodError => e
    raise unless e.message.include?("nil")
    nil
  end

  def method_missing(name, *args)
    key = name.to_s.downcase
    return @ports[key] if @ports.key?(key)
    return @params[key] if @params.key?(key)
    super
  end

  def respond_to_missing?(name, _ = false) = @ports.key?(name.to_s.downcase) || @params.key?(name.to_s.downcase) || super
end

def translate(expr)
  expr.dup.tap do |e|
    { "IIF(" => "iif(", "ISNULL(" => "isnull(", "DECODE(" => "decode(",
      "MONTHS_BETWEEN(" => "months_between(", "TRUNC(" => "trunc(",
      "ROUND(" => "pc_round(", "GET_DATE_PART(" => "get_date_part(" }.each { |a, b| e.gsub!(a, b) }
    e.gsub!(/\$\$(\w+)/) { $1 }                    # workflow variables → params
    e.gsub!(/\bAND\b/, "&&")
    e.gsub!(/\bOR\b/, "||")
    e.gsub!(/\bNOT\b/, "!")
    e.gsub!(/(?<![<>!=])=(?![=<>])/, "==")         # PC equality → Ruby
    e.gsub!(/(\d)\.(\d+)\b/) { "#{$1}.#{$2}r" }    # decimal literals → Rational
    # Port and variable references are ALL_CAPS in the repository; Ruby would
    # read them as constants. Lower them to method calls, sparing quoted strings.
    e.gsub!(/'[^']*'|\b[A-Z][A-Z0-9_]*\b/) { |m| m.start_with?("'") ? m : m.downcase }
  end
end

# --- Load repository metadata ------------------------------------------------

doc = REXML::Document.new(File.read(File.join(__dir__, "WF_M_PENS_CALC_03.XML")))
FOLDER = doc.elements["POWERMART/REPOSITORY/FOLDER"]

def mapping(name) = FOLDER.elements["MAPPING[@NAME='#{name}']"]

def transform_fields(mapping_name, transformation_name)
  mapping(mapping_name)
    .elements["TRANSFORMATION[@NAME='#{transformation_name}']"]
    .get_elements("TRANSFORMFIELD")
    .map { |tf| [tf.attributes["NAME"], tf.attributes["PORTTYPE"], translate(tf.attributes["EXPRESSION"])] }
end

def session_order
  links = FOLDER.get_elements("WORKFLOW/WORKFLOWLINK").map { |l| [l.attributes["FROMTASK"], l.attributes["TOTASK"]] }
  order, cursor = [], "Start"
  while (link = links.find { |from, _| from == cursor })
    order << link[1]
    cursor = link[1]
  end
  order
end

def read_csv(file)
  lines = File.readlines(File.join(INPUT, file), chomp: true)
  header = lines.shift.split(",")
  lines.map { |l| header.zip(l.split(",", -1)).to_h }
end

def date(s) = (s.nil? || s.empty?) ? nil : Date.iso8601(s)
def money(s) = s.to_r

PARAMS = { "run_prd_end" => RUN_PRD_END }

# --- Session implementations (engine semantics per mapping) -------------------

# s_m_SAL_EFF_01: effective salary per member-year. Engine reads the salary
# file sequentially into (member, year) — a later row for the same key
# replaces the earlier one. Lookup policy from the XML: latest POSTED_DT wins,
# adjustments invisible until posted (POSTED_DT <= $$RUN_PRD_END).
def run_s_m_sal_eff_01
  adj = Hash.new { |h, k| h[k] = [] }
  read_csv("adjustments.csv").each do |r|
    next unless date(r["posted_date"]) <= RUN_PRD_END
    adj[[r["member_id"], date(r["effective_date"]).year]] << [date(r["posted_date"]), money(r["corrected_annual_salary"])]
  end

  _, _, eff_sal_expr = transform_fields("m_SAL_EFF_01", "EXP_EFF_SAL").first

  rows = {}
  read_csv("salary_history.csv").each do |r|
    yr = date(r["effective_date"]).year
    rows[[r["member_id"], yr]] = money(r["annual_salary"])
  end

  rows.map do |(mbr, yr), ann_sal|
    corr = adj[[mbr, yr]].max_by(&:first)&.last
    ctx = ExprContext.new(PARAMS)
    ctx["ANN_SAL"] = ann_sal
    ctx["CORR_ANN_SAL"] = corr
    { "MBR_ID" => mbr, "EFF_YR" => yr, "EFF_SAL" => ctx.evaluate(eff_sal_expr) }
  end
end

# s_m_SVC_VEST_02: service, vesting, factors — every rule evaluated straight
# from the XML's port expressions, in port order; then the XML's filter.
def run_s_m_svc_vest_02
  ports = transform_fields("m_SVC_VEST_02", "EXP_SVC")
  filter = translate(mapping("m_SVC_VEST_02")
    .elements["TRANSFORMATION[@NAME='FIL_PAYABLE']/TABLEATTRIBUTE[@NAME='Filter Condition']"]
    .attributes["VALUE"])

  read_csv("members.csv").filter_map do |r|
    ctx = ExprContext.new(PARAMS)
    ctx["MBR_ID"] = r["member_id"]
    ctx["BIRTH_DT"] = date(r["birth_date"])
    ctx["HIRE_DT"] = date(r["hire_date"])
    ctx["PRI_TERM_DT"] = date(r["prior_termination_date"])
    ctx["REHIRE_DT"] = date(r["rehire_date"])
    ctx["TERM_DT"] = date(r["termination_date"])
    ctx["RET_DT"] = date(r["retirement_date"])
    ctx["PLAN_CD"] = r["plan_tier"]
    ctx["SURV_OPT"] = r["survivor_option"]
    ports.each { |name, _, expr| ctx[name] = ctx.evaluate(expr) }
    next unless ctx.evaluate(filter)
    ctx.to_h.slice("MBR_ID", "SVC_YRS", "EARLY_FCT", "SURV_FCT", "ACCR_RT")
  end
end

# s_m_BEN_CALC_03: sorter (MBR ASC, YR DESC), then the variable-port window
# scan — ports evaluated in document order, variables persisting across rows,
# exactly as the Integration Service treats an Expression transformation.
# Aggregator takes LAST per member; joiner; final benefit expression.
def run_s_m_ben_calc_03(sal_eff, svc_vest)
  win_ports = transform_fields("m_BEN_CALC_03", "EXP_FAS_WIN")
  _, _, ben_expr = transform_fields("m_BEN_CALC_03", "EXP_BEN").first

  sorted = sal_eff.sort_by { |r| [r["MBR_ID"], -r["EFF_YR"]] }

  ctx = ExprContext.new(PARAMS)
  %w[V_YR_RNK V_WIN_SUM V_FAS_MAX V_SAL_1 V_SAL_2].each { |v| ctx[v] = 0r }
  ctx["V_PREV_MBR"] = ""

  fas_by_member = {}
  sorted.each do |row|
    ctx["MBR_ID"] = row["MBR_ID"]
    ctx["EFF_SAL"] = row["EFF_SAL"]
    win_ports.each { |name, _, expr| ctx[name] = ctx.evaluate(expr) }
    fas_by_member[row["MBR_ID"]] = ctx["FAS_OUT"] # aggregator: LAST per group
  end

  svc_vest.filter_map do |svc|
    fas = fas_by_member[svc["MBR_ID"]] or next # joiner: Normal Join drops unmatched
    bctx = ExprContext.new(PARAMS)
    bctx["FAS"] = fas
    svc.each { |k, v| bctx[k] = v }
    bctx["MO_BEN"] = bctx.evaluate(ben_expr)
    bctx.to_h.slice("MBR_ID", "SVC_YRS", "FAS", "EARLY_FCT", "SURV_FCT", "MO_BEN")
  end
end

# --- Run the workflow ---------------------------------------------------------

FileUtils.mkdir_p(STAGING)
FileUtils.mkdir_p(GOLDEN)

results = {}
session_order.each do |session|
  case session
  when "s_m_SAL_EFF_01"  then results[:sal_eff] = run_s_m_sal_eff_01
  when "s_m_SVC_VEST_02" then results[:svc_vest] = run_s_m_svc_vest_02
  when "s_m_BEN_CALC_03" then results[:ben_pay] = run_s_m_ben_calc_03(results[:sal_eff], results[:svc_vest])
  else raise "unknown session: #{session}"
  end
  puts format("%-18s SUCCEEDED", session)
end

def fmt(x, scale) = ("%.#{scale}f" % x)

out_file = File.join(GOLDEN, "BEN_PAY_#{ARGV[0]}.csv")
rows = results[:ben_pay].sort_by { |r| r["MBR_ID"] }
File.open(out_file, "w") do |f|
  f.puts "member_id,svc_yrs,fas,early_fct,surv_fct,mo_ben"
  rows.each do |r|
    f.puts [r["MBR_ID"], fmt(r["SVC_YRS"], 4), fmt(r["FAS"], 2),
            fmt(r["EARLY_FCT"], 4), fmt(r["SURV_FCT"], 4), fmt(r["MO_BEN"], 2)].join(",")
  end
end

total = rows.sum { |r| r["MO_BEN"] }
manifest = {
  workflow: "WF_M_PENS_CALC_03",
  run_period: ARGV[0],
  members_in: read_csv("members.csv").size,
  payable: rows.size,
  total_monthly_benefit: fmt(total, 2),
  input_manifest_sha256: Digest::SHA256.file(File.join(INPUT, "manifest.json")).hexdigest,
  output_sha256: Digest::SHA256.file(out_file).hexdigest
}
File.write(File.join(GOLDEN, "manifest_#{ARGV[0]}.json"), JSON.pretty_generate(manifest) + "\n")

puts "payable:  #{rows.size} of #{manifest[:members_in]}"
puts "total:    $#{fmt(total, 2)}/month"
puts "golden:   #{out_file}"
