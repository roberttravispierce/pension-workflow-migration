module Pension
  # Monthly benefit for one payable member.
  #
  # Final average salary: the best average over three consecutive calendar
  # years within the member's final ten calendar years of employment.
  # Monthly benefit = FAS x accrual rate x service years x early factor
  # x survivor factor / 12, rounded to the cent.
  class BenefitCalculator
    WINDOW_YEARS = 3
    SPAN_YEARS = 10

    def initialize(service:, salaries_by_year:, termination_year:)
      @service = service
      @salaries = salaries_by_year
      @final_span = (termination_year - SPAN_YEARS + 1)..termination_year
    end

    def final_average_salary
      windows = @final_span.each_cons(WINDOW_YEARS).filter_map do |years|
        values = years.map { |y| @salaries[y] }
        values.sum / WINDOW_YEARS unless values.any?(&:nil?)
      end
      windows.max || 0r
    end

    def monthly_benefit
      (final_average_salary *
        @service.accrual_rate *
        @service.service_years *
        @service.early_factor *
        @service.survivor_factor / 12).round(2, half: :up)
    end
  end
end
