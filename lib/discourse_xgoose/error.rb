# frozen_string_literal: true
module DiscourseXgoose
  class Error < StandardError
    attr_reader :code, :status
    def initialize(code, status = 422)
      @code, @status = code, status
      super(code)
    end
  end
end
