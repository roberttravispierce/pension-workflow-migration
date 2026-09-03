module Pension
  # Credited service, vesting, and benefit factors for one member.
  # Service accrues over the employment period; a rehired member's service
  # is measured from the rehire date. Vesting at five years. Early
  # retirement reduces 0.5% per whole month before age 65; survivor
  # options carry fixed factors; accrual rate is set by plan tier.
  class ServiceCalculator
    VESTING_YEARS = 5
    NORMAL_RETIREMENT_MONTHS = 65 * 12
    EARLY_REDUCTION_PER_MONTH = "0.005".to_r
    SURVIVOR_FACTORS = { "js50" => "0.90".to_r, "js100" => "0.84".to_r }.freeze
    ACCRUAL_RATES = { "clergy" => "0.0175".to_r, "lay" => "0.015".to_r }.freeze

    Result = Struct.new(:member_id, :service_years, :early_factor, :survivor_factor, :accrual_rate, keyword_init: true)

    def initialize(member)
      @m = member
    end

    def payable_for?(period_end)
      retirement && retirement <= period_end && vested?
    end

    def result
      Result.new(
        member_id: @m["member_id"],
        service_years: service_years,
        early_factor: early_factor,
        survivor_factor: SURVIVOR_FACTORS.fetch(@m["survivor_option"], 1r),
        accrual_rate: ACCRUAL_RATES.fetch(@m["plan_tier"], 0r)
      )
    end

    private

    def date(field)
      v = @m[field]
      v.nil? || v.empty? ? nil : Date.iso8601(v)
    end

    def retirement = date("retirement_date")

    def service_years
      from = date("rehire_date") || date("hire_date")
      months = months_between(date("termination_date"), from)
      truncate(months / 12, 4)
    end

    def vested? = service_years >= VESTING_YEARS

    def early_factor
      age_months = months_between(retirement, date("birth_date"))
      return 1r if age_months >= NORMAL_RETIREMENT_MONTHS

      months_early = (NORMAL_RETIREMENT_MONTHS - age_months).truncate
      1r - EARLY_REDUCTION_PER_MONTH * months_early
    end

    def months_between(later, earlier)
      whole = (later.year - earlier.year) * 12 + (later.month - earlier.month)
      Rational(whole) + Rational(later.day - earlier.day, 31)
    end

    def truncate(x, digits)
      Rational((x * 10**digits).to_i, 10**digits)
    end
  end
end
