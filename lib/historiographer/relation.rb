module Historiographer
  module Relation
    extend ActiveSupport::Concern

    def has_histories?
      self.klass.respond_to?(:history_class)
    end

    def update_all_without_history(updates)
      update_all(updates, false)
    end

    def update_all(updates, histories=true)
      unless histories
        super(updates)
      else
        updates.symbolize_keys!

        ActiveRecord::Base.transaction do
          super(updates.except(:history_user_id))
          now = UTC.now
          records = self.reload
          history_class = records.klass.history_class

          records.new.send(:history_user_absent_action) if updates[:history_user_id].nil?
          history_user_id = updates[:history_user_id]

          new_histories = records.map do |record|
            attrs         = record.attributes.clone
            foreign_key   = history_class.history_foreign_key
      
            now = UTC.now
            attrs.merge!(foreign_key => attrs["id"], history_started_at: now, history_user_id: history_user_id)
      
            attrs = attrs.except("id")

            record.histories.build(attrs)
          end

          current_histories = history_class.current.where("#{history_class.history_foreign_key} IN (?)", records.map(&:id))

          current_histories.update_all(history_ended_at: now)

          history_class.import new_histories
        end
      end
    end

    def delete_all_without_history
      delete_all(nil, false)
    end

    def delete_all(options={}, histories=true)
      unless histories
        super()
      else
        ActiveRecord::Base.transaction do
          records = self
          history_class = records.first.class.history_class
          history_user_id = options[:history_user_id]
          records.first.send(:history_user_absent_action) if history_user_id.nil?
          now = UTC.now

          history_class.current.where("#{history_class.history_foreign_key} IN (?)", records.map(&:id)).update_all(history_ended_at: now)

          if records.first.respond_to?(:paranoia_destroy)
            new_histories = records.map do |record|
              attrs         = record.attributes.clone
              foreign_key   = history_class.history_foreign_key
        
              now = UTC.now
              attrs.merge!(foreign_key => attrs["id"], history_started_at: now, history_user_id: history_user_id, deleted_at: now)
        
              attrs = attrs.except("id")

              record.histories.build(attrs)
            end
            history_class.import new_histories
          end

          super()
        end
      end
    end

    def destroy_all(history_user_id: nil)
      records.each { |r| r.destroy(history_user_id: history_user_id) }.tap { reset }
    end
  end
end