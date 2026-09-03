# Mechanical ground-truth check: the generated documentation's inventory
# claims, diffed against the repository export itself. An AI-written document
# that miscounts objects reads exactly as plausibly as one that doesn't —
# so the counts are never taken on faith.
#
# Usage: ruby script/doc_check.rb

require "rexml/document"

ROOT = File.expand_path("..", __dir__)
xml = REXML::Document.new(File.read(File.join(ROOT, "legacy/WF_M_PENS_CALC_03.XML")))
doc = File.read(File.join(ROOT, "docs/legacy/WF_M_PENS_CALC_03.md"))
folder = xml.elements["POWERMART/REPOSITORY/FOLDER"]

actual = {
  "Mappings" => folder.get_elements("MAPPING").size,
  "Sessions" => folder.get_elements("SESSION").size,
  "Transformations" => folder.get_elements("MAPPING/TRANSFORMATION").size,
  "Expression ports carrying business rules" =>
    folder.get_elements("MAPPING/TRANSFORMATION/TRANSFORMFIELD")
          .count { |tf| tf.attributes["EXPRESSION"] }
}

claimed = doc.scan(/^\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|/).to_h { |k, v| [k, v.to_i] }

failures = 0
actual.each do |claim, truth|
  stated = claimed[claim]
  ok = stated == truth
  failures += 1 unless ok
  puts format("%-42s doc=%-4s export=%-4s %s", claim, stated.inspect, truth, ok ? "PASS" : "FAIL")
end

sequence = folder.get_elements("WORKFLOW/WORKFLOWLINK")
  .map { |l| l.attributes["TOTASK"] }
seq_claimed = doc[/Sequence: (.+)\./, 1].to_s.delete("`").split(" → ")
seq_ok = sequence == seq_claimed
failures += 1 unless seq_ok
puts format("%-42s %s", "Session sequence", seq_ok ? "PASS" : "FAIL (doc: #{seq_claimed.join(' -> ')}; export: #{sequence.join(' -> ')})")

puts failures.zero? ? "\nDOC CHECK CLEAN — inventory claims match the export" :
                      "\nDOC CHECK: #{failures} claim(s) contradict the export — do not route to expert review yet"
exit(failures.zero? ? 0 : 1)
