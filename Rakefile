# frozen_string_literal: true

require "rake/testtask"
require 'bundler'

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

Bundler::GemHelper.install_tasks

task default: :test
