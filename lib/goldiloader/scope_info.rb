# frozen_string_literal: true

module Goldiloader
  class ScopeInfo
    attr_reader :scope

    def initialize(scope)
      @scope = scope
    end

    def offset?
      scope.offset_value.present?
    end

    def limit?
      scope.limit_value.present?
    end

    def auto_include?
      return scope.auto_include_value unless scope.auto_include_value.nil?
      Goldiloader.auto_include
    end

    def from?
      scope.from_clause.present?
    end

    def group?
      scope.group_values.present?
    end

    def order?
      scope.order_values.present?
    end
  end
end
