require 'spec_helper'

describe 'SP initiated sign up' do
  before { inbox_clear }

  it 'creates new account via SP' do
    visit sp_url
    if sp_url == usa_jobs_url
      click_button 'Continue'
    else
      find(:css, '.btn').click
    end

    expect(current_url).to match(%r{https://idp})

    click_on 'Create an account'
    create_new_account_with_sms

    expect(current_path).to eq '/sign_up/completed'

    click_on 'Continue'

    if sp_url == usa_jobs_url
      expect(current_url).to match(%r{https://.+\.uat\.usajobs\.gov})
    else
      expect(current_url).to match(%r{https://sp})
      expect(page).to have_content(email_address)
    end
  end
end
