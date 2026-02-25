require 'rails_helper'

RSpec.describe Abilities, type: :model do
  describe '.can?' do
    describe 'create scheduled meeting' do
      it 'allows users with full permission' do
        room = Room.create!(consumer_key: 'consumer-1')
        user = User.new(uid: 'teacher-1', roles: 'Admin', launch_nonce: 'nonce-teacher')

        expect(Abilities.can?(user, :create_scheduled_meeting, room)).to be(true)
      end

      it 'allows regular users when allow_student_scheduling is enabled' do
        ConsumerConfig.create!(key: 'consumer-2', allow_student_scheduling: true)
        room = Room.create!(consumer_key: 'consumer-2')
        user = User.new(uid: 'student-1', roles: 'Student', launch_nonce: 'nonce-student')

        expect(Abilities.can?(user, :create_scheduled_meeting, room)).to be(true)
      end

      it 'denies regular users when allow_student_scheduling is disabled' do
        ConsumerConfig.create!(key: 'consumer-3', allow_student_scheduling: false)
        room = Room.create!(consumer_key: 'consumer-3')
        user = User.new(uid: 'student-2', roles: 'Student', launch_nonce: 'nonce-student-2')

        expect(Abilities.can?(user, :create_scheduled_meeting, room)).to be(false)
      end
    end

    describe 'manage scheduled meeting' do
      it 'allows users with full permission' do
        room = Room.create!(consumer_key: 'consumer-4')
        meeting = ScheduledMeeting.create!(
          room: room,
          name: 'Weekly class',
          start_at: Time.zone.now + 1.hour,
          duration: 1800,
          created_by_launch_nonce: 'nonce-creator'
        )
        user = User.new(uid: 'teacher-2', roles: 'Admin', launch_nonce: 'nonce-other')

        expect(Abilities.can?(user, :manage_scheduled_meeting, meeting)).to be(true)
      end

      it 'allows the creator via app launch nonce' do
        room = Room.create!(consumer_key: 'consumer-5')
        AppLaunch.create!(
          nonce: 'nonce-student-creator',
          params: {
            'user_id' => 'student-3',
            'context_id' => 'context-5',
            'tool_consumer_instance_guid' => 'consumer-5',
            'resource_link_id' => 'resource-5',
            'custom_params' => { 'custom_enable_groups_scoping' => 'false' }
          },
          expires_at: Time.zone.now + 1.hour
        )
        meeting = ScheduledMeeting.create!(
          room: room,
          name: 'Office hours',
          start_at: Time.zone.now + 1.hour,
          duration: 1800,
          created_by_launch_nonce: 'nonce-student-creator'
        )
        user = User.new(uid: 'student-3', roles: 'Student', launch_nonce: 'nonce-student-creator')

        expect(Abilities.can?(user, :manage_scheduled_meeting, meeting)).to be(true)
      end

      it 'denies non-creator students' do
        room = Room.create!(consumer_key: 'consumer-7')
        AppLaunch.create!(
          nonce: 'nonce-owner',
          params: {
            'user_id' => 'student-owner',
            'context_id' => 'context-7',
            'tool_consumer_instance_guid' => 'consumer-7',
            'resource_link_id' => 'resource-7',
            'custom_params' => { 'custom_enable_groups_scoping' => 'false' }
          },
          expires_at: Time.zone.now + 1.hour
        )
        meeting = ScheduledMeeting.create!(
          room: room,
          name: 'Lab',
          start_at: Time.zone.now + 1.hour,
          duration: 1800,
          created_by_launch_nonce: 'nonce-owner'
        )
        user = User.new(uid: 'student-other', roles: 'Student', launch_nonce: 'nonce-other')

        expect(Abilities.can?(user, :manage_scheduled_meeting, meeting)).to be(false)
      end

      it 'denies access when app launch is missing (expired/deleted)' do
        room = Room.create!(consumer_key: 'consumer-8')
        meeting = ScheduledMeeting.create!(
          room: room,
          name: 'Old meeting',
          start_at: Time.zone.now + 1.hour,
          duration: 1800,
          created_by_launch_nonce: 'nonce-expired'
        )
        user = User.new(uid: 'student-4', roles: 'Student', launch_nonce: 'nonce-student-4')

        expect(Abilities.can?(user, :manage_scheduled_meeting, meeting)).to be(false)
      end
    end
  end
end
