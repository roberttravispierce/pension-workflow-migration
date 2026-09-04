# Field-level reconciliation of the migrated output against the golden
# legacy output. Checks escalate: row count, member set, checksums, column
# totals, then a full per-member per-field diff — because on pension
# amounts, sampling is not evidence and "same number of rows" is not
# correctness.
#
# Exit status is nonzero when any field differs.
#
# Usage: ruby script/reconcile.rb 2026-09

require "digest"
require "fileutils"

period = ARGV[0] or abort "usage: ruby script/reconcile.rb YYYY-MM"
ROOT = File.expand_path("..", __dir__)
golden_path = File.join(ROOT, "data/golden/BEN_PAY_#{period}.csv")
output_path = File.join(ROOT, "data/output/BEN_PAY_#{period}.csv")

def load(path)
  lines = File.readlines(path, chomp: true)
  header = lines.shift.split(",")
  rows = lines.map { |l| header.zip(l.split(",", -1)).to_h }
  [ header, rows.to_h { |r| [ r["member_id"], r ] } ]
end

header, golden = load(golden_path)
_, output = load(output_path)
fields = header - [ "member_id" ]

report = []
rel = ->(p) { p.sub("#{ROOT}/", "") }
report << "RECONCILIATION — BEN_PAY #{period}"
report << "golden: #{rel.call(golden_path)} (sha256 #{Digest::SHA256.file(golden_path).hexdigest[0, 12]}…)"
report << "output: #{rel.call(output_path)} (sha256 #{Digest::SHA256.file(output_path).hexdigest[0, 12]}…)"
report << ""

failures = 0

# 1. Row count
report << format("%-28s golden=%d output=%d  %s", "1. row count",
                 golden.size, output.size, golden.size == output.size ? "PASS" : "FAIL")
failures += 1 unless golden.size == output.size

# 2. Member set
missing = golden.keys - output.keys
extra = output.keys - golden.keys
set_ok = missing.empty? && extra.empty?
report << format("%-28s %s", "2. member set", set_ok ? "PASS" : "FAIL")
report << "   missing from output: #{missing.join(', ')}" unless missing.empty?
report << "   unexpected in output: #{extra.join(', ')}" unless extra.empty?
failures += 1 unless set_ok

# 3. Checksums
sums_match = Digest::SHA256.file(golden_path) == Digest::SHA256.file(output_path)
report << format("%-28s %s", "3. file checksum", sums_match ? "PASS" : "FAIL")
failures += 1 unless sums_match

# 4. Column totals
report << "4. column totals"
fields.each do |f|
  g = golden.values.sum { |r| r[f].to_r }
  o = output.each_value.sum { |r| r[f].to_r }
  delta = o - g
  report << format("   %-12s golden=%14.2f output=%14.2f delta=%+.2f  %s",
                   f, g, o, delta, delta.zero? ? "PASS" : "FAIL")
  failures += 1 unless delta.zero?
end

# 5. Field-level diff — every member, every field, exact match required
diffs = []
golden.each do |member_id, g|
  o = output[member_id] or next
  fields.each do |f|
    next if g[f] == o[f]
    diffs << { member: member_id, field: f, golden: g[f], output: o[f],
               delta: (o[f].to_r - g[f].to_r) }
  end
end

report << format("5. field-level diff           %d field(s) differ across %d member(s)  %s",
                 diffs.size, diffs.map { |d| d[:member] }.uniq.size, diffs.empty? ? "PASS" : "FAIL")
failures += diffs.size

by_field = diffs.group_by { |d| d[:field] }
by_field.each do |field, ds|
  report << "   #{field}: #{ds.size} member(s)"
  ds.sort_by { |d| -d[:delta].abs }.first(15).each do |d|
    report << format("     %-12s golden=%-12s output=%-12s delta=%+.4f",
                     d[:member], d[:golden], d[:output], d[:delta].to_f)
  end
  report << "     … #{ds.size - 15} more" if ds.size > 15
end

report << ""
report << (failures.zero? ? "RESULT: CLEAN — outputs identical" :
           "RESULT: #{failures} discrepanc#{failures == 1 ? 'y' : 'ies'} — DO NOT CUT OVER")

recon_dir = File.join(ROOT, "data/reconciliation")
FileUtils.mkdir_p(recon_dir)
File.write(File.join(recon_dir, "RECON_#{period}.txt"), report.join("\n") + "\n")

puts report.join("\n")
exit(failures.zero? ? 0 : 1)
