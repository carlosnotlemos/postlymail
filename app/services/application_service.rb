class ApplicationService
  class Result
    attr_reader :data, :error, :error_code

    def initialize(success:, data: nil, error: nil, error_code: nil)
      @success = success
      @data = data
      @error = error
      @error_code = error_code
      freeze
    end

    def success?
      @success
    end

    def failure?
      !@success
    end
  end

  def self.call(...)
    new(...).call
  end

  private

  def success(data = nil)
    Result.new(success: true, data: data)
  end

  def failure(error, error_code = nil, data: nil, **kwargs)
    code = error_code || kwargs[:error_code]
    payload = data || kwargs[:data]
    Result.new(success: false, error: error, error_code: code, data: payload)
  end
end
