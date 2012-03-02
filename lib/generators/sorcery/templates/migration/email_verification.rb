class SorceryEmailVerification < ActiveRecord::Migration
  def self.up
    add_column :<%= model_class_name.tableize %>, :pending_email, :string, :default => nil
  end

  def self.down
    remove_column :<%= model_class_name.tableize %>, :pending_email
  end
end
