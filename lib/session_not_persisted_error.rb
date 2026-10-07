# frozen_string_literal: true

# Raised (never actually raised, only instantiated) to notify by e-mail that an LTI launch
# ended on the retry page because the session written before the OAuth round trip did not
# survive it. It is not a 500, so ExceptionNotifier has to be called explicitly.
class SessionNotPersistedError < StandardError; end
