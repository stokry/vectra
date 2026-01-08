# frozen_string_literal: true

class EnablePgvectorExtension < ActiveRecord::Migration<%= migration_version %>
  def up
    enable_extension 'vector'
  end

  def down
    disable_extension 'vector'
  end
end
