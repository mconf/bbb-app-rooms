class AddAllowStudentSchedulingToConsumerConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :consumer_configs, :allow_student_scheduling, :boolean, default: false, null: false
  end
end
