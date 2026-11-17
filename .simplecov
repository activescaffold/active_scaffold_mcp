# frozen_string_literal: true

SimpleCov.configure do
  skip '/test/'
  cover '{app,lib}/**/*.rb'
  enable_coverage :branch
  primary_coverage :line
end

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::JSONFormatter
]
