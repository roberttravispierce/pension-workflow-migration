# Generates the frozen input dataset for the migration lab.
#
# Deterministic: same SEED, same output, byte for byte. No clock reads —
# reproducibility is the point, because this input is the fixed ground both
# the legacy runner and the Temporal implementation are judged against.
#
# Usage: ruby script/generate_dataset.rb [bulk_count]

require "json"
require "digest"
require "date"
require "fileutils"

SEED = 20_260_902
RUN_PERIOD = "2026-09"
OUT_DIR = File.expand_path("../data/input", __dir__)

BULK_COUNT = (ARGV[0] || 1_000).to_i
rng = Random.new(SEED)

Member = Struct.new(:id, :birth_date, :hire_date, :prior_termination_date,
                    :rehire_date, :termination_date, :retirement_date,
                    :plan_tier, :survivor_option,
                    keyword_init: true)

members = []
salaries = []    # [member_id, effective_date, annual_salary]
adjustments = [] # [member_id, effective_date, posted_date, corrected_annual_salary, reason]

# --- Bulk population -------------------------------------------------------

BULK_COUNT.times do |i|
  id = format("MBR-%05d", i + 1)
  birth_year = 1946 + rng.rand(30)                # 1946..1975
  birth = Date.new(birth_year, 1 + rng.rand(12), 1 + rng.rand(28))
  hire_age = 24 + rng.rand(20)
  hire = Date.new(birth_year + hire_age, 1 + rng.rand(12), 1 + rng.rand(28))
  tier = rng.rand < 0.6 ? "clergy" : "lay"
  survivor = %w[none js50 js100][rng.rand(3)]

  # About 70% are already retired (they are who a benefit run pays).
  retirement = nil
  if rng.rand < 0.7
    ret_age = 60 + rng.rand(11)                   # 60..70
    retirement = hire >> ((ret_age - hire_age) * 12 + rng.rand(12))
    retirement = Date.new(retirement.year, retirement.month, 1)
  end

  members << Member.new(id: id, birth_date: birth, hire_date: hire,
                        termination_date: retirement, retirement_date: retirement,
                        plan_tier: tier, survivor_option: survivor)

  # Salary history: annual raises from hire to termination (or 2026).
  base = 28_000 + rng.rand(45_000)
  last_year = (retirement || Date.new(2026, 9, 1)).year
  (hire.year..last_year).each do |year|
    salary = (base * (1.028**(year - hire.year))).round(2)
    salaries << [id, Date.new(year, 1, 1), salary]
  end

  # ~8% of retirees have a routine retroactive correction.
  next unless retirement && rng.rand < 0.08
  eff_year = retirement.year - 1 - rng.rand(3)
  original = salaries.find { |mid, d, _| mid == id && d.year == eff_year }
  next unless original
  adjustments << [id, original[1], retirement >> rng.rand(1..6),
                  (original[2] * 1.03).round(2), "late-reported compensation"]
end

# --- Curated edge members ---------------------------------------------------
# Each plants exactly one trap. Known IDs, fully hand-specified, documented here
# and nowhere else — the legacy workflow is the only "documentation" of how
# they are meant to be handled, which is the entire point of the simulation.

def edge(members, salaries, **attrs)
  m = Member.new(**attrs)
  members << m
  m
end

def yearly(salaries, id, from_year, to_year, base, raise_pct: 0.03)
  (from_year..to_year).each do |y|
    salaries << [id, Date.new(y, 1, 1), (base * ((1 + raise_pct)**(y - from_year))).round(2)]
  end
end

# EDGE-0001 — retroactive adjustment POSTED after retirement, EFFECTIVE before.
# The run must recompute final average salary as of the effective date.
edge(members, salaries,
     id: "EDGE-0001", birth_date: Date.new(1958, 4, 15), hire_date: Date.new(1990, 6, 1),
     termination_date: Date.new(2023, 5, 1), retirement_date: Date.new(2023, 5, 1),
     plan_tier: "clergy", survivor_option: "none")
yearly(salaries, "EDGE-0001", 1990, 2023, 41_000)
adjustments << ["EDGE-0001", Date.new(2021, 1, 1), Date.new(2024, 2, 10), 78_400.00,
                "compensation restated after audit"]

# EDGE-0002 — early retirement at 62: reduction applies (0.5%/month before 65).
edge(members, salaries,
     id: "EDGE-0002", birth_date: Date.new(1962, 8, 1), hire_date: Date.new(1995, 3, 1),
     termination_date: Date.new(2024, 8, 1), retirement_date: Date.new(2024, 8, 1),
     plan_tier: "lay", survivor_option: "js50")
yearly(salaries, "EDGE-0002", 1995, 2024, 39_500)

# EDGE-0003 — exactly 5.000 years of service: vesting boundary, inclusive.
edge(members, salaries,
     id: "EDGE-0003", birth_date: Date.new(1959, 1, 1), hire_date: Date.new(2019, 9, 1),
     termination_date: Date.new(2024, 9, 1), retirement_date: Date.new(2024, 9, 1),
     plan_tier: "lay", survivor_option: "none")
yearly(salaries, "EDGE-0003", 2019, 2024, 52_000)

# EDGE-0004 — 4 years 11 months: NOT vested. Correct output is no benefit.
edge(members, salaries,
     id: "EDGE-0004", birth_date: Date.new(1959, 1, 1), hire_date: Date.new(2019, 10, 1),
     termination_date: Date.new(2024, 9, 1), retirement_date: Date.new(2024, 9, 1),
     plan_tier: "lay", survivor_option: "none")
yearly(salaries, "EDGE-0004", 2019, 2024, 52_000)

# EDGE-0005 — 100% joint & survivor: heaviest option factor.
edge(members, salaries,
     id: "EDGE-0005", birth_date: Date.new(1955, 12, 3), hire_date: Date.new(1988, 1, 15),
     termination_date: Date.new(2021, 1, 1), retirement_date: Date.new(2021, 1, 1),
     plan_tier: "clergy", survivor_option: "js100")
yearly(salaries, "EDGE-0005", 1988, 2020, 44_250)

# EDGE-0006 — unpaid leave INSIDE the averaging window: no salary row for
# 2018, with peak earnings straddling the gap and a phased-retirement decline
# after it. Whether an averaging window may span the missing year is a
# business rule nobody wrote down; only the legacy run defines it.
edge(members, salaries,
     id: "EDGE-0006", birth_date: Date.new(1957, 6, 20), hire_date: Date.new(1992, 9, 1),
     termination_date: Date.new(2022, 6, 1), retirement_date: Date.new(2022, 6, 1),
     plan_tier: "clergy", survivor_option: "js50")
yearly(salaries, "EDGE-0006", 1992, 2014, 37_800)
{ 2015 => 78_000, 2016 => 82_000, 2017 => 82_000,
  2019 => 82_000, 2020 => 52_000, 2021 => 52_000, 2022 => 52_000 }.each do |y, sal|
  salaries << ["EDGE-0006", Date.new(y, 1, 1), sal]
end

# EDGE-0007 — identical data to a normal member, but salary rows arrive
# OUT OF ORDER in the file. Order sensitivity is a classic silent divergence.
edge(members, salaries,
     id: "EDGE-0007", birth_date: Date.new(1960, 2, 10), hire_date: Date.new(1994, 4, 1),
     termination_date: Date.new(2025, 1, 1), retirement_date: Date.new(2025, 1, 1),
     plan_tier: "lay", survivor_option: "none")
edge_rows = []
(1994..2024).each do |y|
  edge_rows << ["EDGE-0007", Date.new(y, 1, 1), (36_000 * (1.03**(y - 1994))).round(2)]
end
shuffled = edge_rows.shuffle(random: Random.new(7))
salaries.concat(shuffled)

# EDGE-0008 — duplicate effective date INSIDE the top averaging window: two
# rows for 2024, the correction appearing later in the file. Which row wins
# decides the member's whole FAS window. Nobody wrote that rule down either.
edge(members, salaries,
     id: "EDGE-0008", birth_date: Date.new(1961, 11, 5), hire_date: Date.new(1996, 7, 1),
     termination_date: Date.new(2026, 7, 1), retirement_date: Date.new(2026, 7, 1),
     plan_tier: "clergy", survivor_option: "none")
yearly(salaries, "EDGE-0008", 1996, 2025, 40_100)
salaries << ["EDGE-0008", Date.new(2024, 1, 1), 71_500.00] # duplicate for 2024

# EDGE-0009 — born February 29. Age-at-retirement arithmetic on a leap birthday.
edge(members, salaries,
     id: "EDGE-0009", birth_date: Date.new(1960, 2, 29), hire_date: Date.new(1993, 5, 1),
     termination_date: Date.new(2025, 3, 1), retirement_date: Date.new(2025, 3, 1),
     plan_tier: "lay", survivor_option: "js50")
yearly(salaries, "EDGE-0009", 1993, 2025, 38_900)

# EDGE-0010 — flat salary for the final decade: every 3-year window ties.
# Which window the legacy picks is observable behavior, not documented intent.
edge(members, salaries,
     id: "EDGE-0010", birth_date: Date.new(1956, 9, 9), hire_date: Date.new(1989, 2, 1),
     termination_date: Date.new(2021, 9, 1), retirement_date: Date.new(2021, 9, 1),
     plan_tier: "clergy", survivor_option: "none")
yearly(salaries, "EDGE-0010", 1989, 2010, 33_000)
(2011..2021).each { |y| salaries << ["EDGE-0010", Date.new(y, 1, 1), 58_000.00] }

# EDGE-0011 — retires mid-month: first benefit month prorated (or not — legacy decides).
edge(members, salaries,
     id: "EDGE-0011", birth_date: Date.new(1958, 3, 25), hire_date: Date.new(1991, 8, 1),
     termination_date: Date.new(2023, 9, 17), retirement_date: Date.new(2023, 9, 17),
     plan_tier: "lay", survivor_option: "none")
yearly(salaries, "EDGE-0011", 1991, 2023, 42_700)

# EDGE-0013 — rehire with prior service: 1992–2001 (vested, 9y4m), gone a
# decade, rehired 2012, retired 2024. Whether prior service bridges into
# credited years — and whether the old salary years count toward the FAS
# window — are business rules only the legacy run can answer.
edge(members, salaries,
     id: "EDGE-0013", birth_date: Date.new(1959, 5, 14), hire_date: Date.new(1992, 3, 1),
     prior_termination_date: Date.new(2001, 6, 30), rehire_date: Date.new(2012, 4, 1),
     termination_date: Date.new(2024, 4, 1), retirement_date: Date.new(2024, 4, 1),
     plan_tier: "clergy", survivor_option: "js50")
yearly(salaries, "EDGE-0013", 1992, 2001, 31_500)
yearly(salaries, "EDGE-0013", 2012, 2024, 54_000)

# EDGE-0012 — salary tuned so the monthly benefit lands on a half cent.
# Where the legacy rounds (per step vs at the end) becomes visible here.
edge(members, salaries,
     id: "EDGE-0012", birth_date: Date.new(1957, 10, 2), hire_date: Date.new(1990, 1, 1),
     termination_date: Date.new(2022, 1, 1), retirement_date: Date.new(2022, 1, 1),
     plan_tier: "clergy", survivor_option: "none")
(1990..2021).each { |y| salaries << ["EDGE-0012", Date.new(y, 1, 1), 51_428.57] }

# --- Write files ------------------------------------------------------------

FileUtils.mkdir_p(OUT_DIR)

def write_csv(path, header, rows)
  File.open(path, "w") do |f|
    f.puts header.join(",")
    rows.each { |r| f.puts r.map { |v| v.is_a?(Date) ? v.iso8601 : v }.join(",") }
  end
end

write_csv(File.join(OUT_DIR, "members.csv"),
          %w[member_id birth_date hire_date prior_termination_date rehire_date termination_date retirement_date plan_tier survivor_option],
          members.map { |m| [m.id, m.birth_date, m.hire_date, m.prior_termination_date, m.rehire_date, m.termination_date, m.retirement_date, m.plan_tier, m.survivor_option] })

write_csv(File.join(OUT_DIR, "salary_history.csv"),
          %w[member_id effective_date annual_salary],
          salaries)

write_csv(File.join(OUT_DIR, "adjustments.csv"),
          %w[member_id effective_date posted_date corrected_annual_salary reason],
          adjustments)

manifest = {
  seed: SEED,
  run_period: RUN_PERIOD,
  bulk_members: BULK_COUNT,
  edge_members: members.count { |m| m.id.start_with?("EDGE-") },
  files: %w[members.csv salary_history.csv adjustments.csv].to_h do |name|
    [name, Digest::SHA256.file(File.join(OUT_DIR, name)).hexdigest]
  end
}
File.write(File.join(OUT_DIR, "manifest.json"), JSON.pretty_generate(manifest) + "\n")

puts "members:     #{members.size} (#{manifest[:edge_members]} edge)"
puts "salaries:    #{salaries.size} rows"
puts "adjustments: #{adjustments.size} rows"
puts "manifest:    #{File.join(OUT_DIR, 'manifest.json')}"
