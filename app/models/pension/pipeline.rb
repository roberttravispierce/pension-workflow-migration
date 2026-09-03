module Pension
  # Filesystem conventions for a benefit run. Activities exchange staged
  # files by these paths — references cross the Temporal boundary, never
  # row data.
  module Pipeline
    module_function

    def input_dir = Rails.root.join("data/input")
    def staging_dir(period) = Rails.root.join("tmp/pipeline", period).tap { |d| FileUtils.mkdir_p(d) }
    def output_dir = Rails.root.join("data/output").tap { |d| FileUtils.mkdir_p(d) }

    def effective_salaries_path(period) = staging_dir(period).join("effective_salaries.csv")
    def payable_path(period) = staging_dir(period).join("payable.csv")
    def shard_path(period, index) = staging_dir(period).join("shard_#{format('%03d', index)}.csv")
    def output_path(period) = output_dir.join("BEN_PAY_#{period}.csv")

    def period_end(period)
      first = Date.parse("#{period}-01")
      Date.new(first.year, first.month, -1)
    end

    def write_rows(path, header, rows)
      File.open(path, "w") do |f|
        f.puts header.join(",")
        rows.each { |r| f.puts r.join(",") }
      end
    end

    def read_rows(path)
      lines = File.readlines(path, chomp: true)
      header = lines.shift.split(",")
      lines.map { |l| header.zip(l.split(",", -1)).to_h }
    end
  end
end
