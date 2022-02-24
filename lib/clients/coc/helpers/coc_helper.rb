module Clients::Coc
  module Helpers
    module CocHelper
      def self.get_class_full_data(schools, class_id)
        return unless schools

        class_id = class_id.to_i
        schools.each do |school|
          school['segments'].each do |segment|
            segment['grades'].each do |grade|
              grade['classes'].each do |klass|
                next unless klass['id'] == class_id

                klass['grade'] = grade
                klass['segment'] = segment
                klass['school'] = school
                return klass
              end
            end
          end
        end

        nil
      end

      def self.classes_count(schools)
        count = 0
        schools.each do |school|
          school['segments'].each do |segment|
            segment['grades'].each do |grade|
              count += grade['classes'].count
            end
          end
        end
        count
      end

      def self.get_single_class(schools)
        schools.first['segments']
               .first['grades']
               .first['classes']
               .first
      end

      def self.sort_schools(schools)
        schools.sort! { |s1, s2| s1['name'] <=> s2['name'] }
        schools.each do |school|
          school['segments'].sort! { |s1, s2| s1['name'] <=> s2['name'] }
          school['segments'].each do |segment|
            segment['grades'].sort! { |g1, g2| g1['name'] <=> g2['name'] }
            segment['grades'].each do |grade|
              grade['classes'].sort! { |c1, c2| c1['name'] <=> c2['name'] }
            end
          end
        end
        schools
      end

      def self.meeting_creator_name(meeting)
        app_launch = AppLaunch.find_by(nonce: meeting.created_by_launch_nonce)
        app_launch.omniauth_auth.dig('info', 'full_name')
      end

      def self.verify_meeting_creator(current_user, meeting)
        app_launch = AppLaunch.find_by(nonce: meeting.created_by_launch_nonce)
        user_creator_id = app_launch.omniauth_auth.dig('uid')
        current_user.uid == user_creator_id
      end
    end
  end
end
