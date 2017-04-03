# use local 'lib' dir in include path
$:.unshift File.dirname(__FILE__)+'/../lib'
require 'json'
require 'pp'
require 'dotenv'
require 'gmail'
require 'capybara/rspec'
require 'capybara/poltergeist'

Capybara.javascript_driver = :poltergeist
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.color = true
  config.order = :random
end

Dotenv.load

PASSWORD = 'salty pickles'.freeze
EMAIL = ENV['EMAIL']
EMAIL_PASSWORD = ENV['EMAIL_PASSWORD']
PHONE = ENV['PHONE']
if !EMAIL or !EMAIL_PASSWORD or !PHONE
  abort("Must set EMAIL EMAIL_PASSWORD and PHONE env vars -- did you create a .env file?")
end

##############################################################################
# helper methods

def idp_signup_url
  ENV['IDP_URL'] + '/sign_up/enter_email'
end

def idp_reset_password_url
  ENV['IDP_URL'] + '/users/password/new'
end

def idp_logout_url
  ENV['IDP_URL'] + '/api/saml/logout'
end

def sp_url
  ENV['SP_URL']
end

def basic_auth_user
  URI.parse(ENV['IDP_URL']).user
end

def basic_auth_pass
  URI.parse(ENV['IDP_URL']).password
end

def random_email_address
  random_str = SecureRandom.hex(3)
  EMAIL.dup.gsub(/@/, "+#{random_str}@")
end

def gmail
  @_gmail ||= Gmail.connect!(EMAIL, EMAIL_PASSWORD)
end

def inbox_unread
  gmail.inbox.emails(:unread)
end

def current_otp_from_email
  inbox_unread.each do |email|
    msg = email.message.parts[0].body
    otp = msg.match(/(\d+) is your login.gov one-time passcode/)[1]
    if otp
      email.read!
      return otp
    end
  end
  nil
end

def current_confirmation_link
  inbox_unread.each do |email|
    next unless email.subject == 'Confirm your email'
    msg = email.message.parts[0].body
    url = msg.match(/(https:.+confirmation_token=[\w\-]+)/)[1]
    if url
      email.read!
      return url
    end
  end
  nil
end

def current_password_reset_link
  inbox_unread.each do |email|
    next unless email.subject == 'Reset your password'
    msg = email.message.parts[0].body
    url = msg.match(/(https:.+reset_password_token=[\w\-]+)/)[1]
    if url
      email.read!
      return url
    end
  end
  nil
end

def check_for_otp
  otp = nil
  counter = 0
  while (!otp) do
    sleep 2
    puts 'checking for OTP...'
    otp = current_otp_from_email
    counter += 1
    if counter >= 60
      puts 'giving up OTP check ... timed out'
      break
    end
  end
  fail 'Cannot find OTP' unless otp
  otp
end

def check_for_confirmation_link
  url = nil
  counter = 0
  while (!url) do
    sleep 2
    puts 'checking for confirmation URL...'
    url = current_confirmation_link
    counter += 1
    if counter >= 60
      puts 'giving up confirmation URL check ... timed out'
      break
    end
  end
  fail 'Cannot find confirmation URL' unless url
  url
end

def check_for_password_reset_link
  url = nil
  counter = 0
  while (!url) do
    sleep 2
    puts 'checking for password reset URL...'
    url = current_password_reset_link
    counter += 1
    if counter >= 60
      puts 'giving up password reset URL check ... timed out'
      break
    end
  end
  fail 'Cannot find password reset URL' unless url
  url
end

def acknowledge_personal_key
  code_words = []

  page.all(:css, '[data-recovery]').map do |node|
    code_words << node.text
  end

  button_text = 'Continue'

  click_on button_text, class: 'recovery-code-continue'

  code_words.size.times do |index|
    fill_in "recovery-#{index}", with: code_words[index].downcase
  end

  click_on button_text, class: 'recovery-code-confirm'

  code_words
end

def create_new_account
  visit idp_signup_url
  email_address = random_email_address
  fill_in 'user_email', with: email_address
  click_on 'Submit'
  confirmation_link = check_for_confirmation_link
  visit confirmation_link
  fill_in 'password_form_password', with: PASSWORD
  click_on 'Submit'
  fill_in 'two_factor_setup_form_phone', with: PHONE
  click_on 'Send passcode'
  otp = check_for_otp
  fill_in 'code', with: otp
  click_on 'Submit'
  code_words = acknowledge_personal_key
  expect(page).to have_content 'Welcome'
  puts "created account for #{email_address} with personal key: #{code_words.join('-')}"
  email_address
end
