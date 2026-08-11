require 'rails_helper'

RSpec.describe Current, type: :model do
  after { Current.reset }

  describe '.record_moodle_call' do
    it 'keeps the calls in the order they happened' do
      Current.record_moodle_call(wsfunction: 'core_webservice_get_site_info', status: 'ok', duration: 0.2111)
      Current.record_moodle_call(
        wsfunction: 'core_course_get_course_module_by_instance',
        status: 'error',
        duration: 0.18,
        errorcode: 'usernotfullysetup'
      )

      expect(Current.moodle_calls).to eq(
        [
          { wsfunction: 'core_webservice_get_site_info', status: 'ok', duration: 0.211 },
          {
            wsfunction: 'core_course_get_course_module_by_instance',
            status: 'error',
            duration: 0.18,
            errorcode: 'usernotfullysetup'
          }
        ]
      )
    end

    it 'omits the errorcode when there is none' do
      Current.record_moodle_call(wsfunction: 'core_group_get_course_user_groups', status: 'ok', duration: 0.1)

      expect(Current.moodle_calls.first).not_to have_key(:errorcode)
    end

    it 'stops recording after the limit' do
      (Current::MAX_MOODLE_CALLS + 5).times do
        Current.record_moodle_call(wsfunction: 'core_webservice_get_site_info', status: 'ok', duration: 0.1)
      end

      expect(Current.moodle_calls.size).to eq(Current::MAX_MOODLE_CALLS)
    end

    it 'does not leak between resets' do
      Current.record_moodle_call(wsfunction: 'core_webservice_get_site_info', status: 'ok', duration: 0.1)
      Current.reset

      expect(Current.moodle_calls).to be_nil
    end
  end

  describe '#log_moodle_calls' do
    it 'logs a single consolidated line on reset' do
      Current.record_moodle_call(wsfunction: 'core_webservice_get_site_info', status: 'ok', duration: 0.211)
      Current.record_moodle_call(
        wsfunction: 'core_course_get_course_module_by_instance',
        status: 'error',
        duration: 0.18,
        errorcode: 'usernotfullysetup'
      )

      expect(Rails.logger).to receive(:info).with(
        '[MOODLE SEQ] calls=2 errors=1 ' \
        '[core_webservice_get_site_info:ok:0.211s, ' \
        'core_course_get_course_module_by_instance:usernotfullysetup:0.18s]'
      )

      Current.reset
    end

    it 'logs nothing when no Moodle call was made' do
      expect(Rails.logger).not_to receive(:info)

      Current.reset
    end
  end
end
