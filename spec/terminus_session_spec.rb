require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Capybara::Session do
  context 'with terminus driver' do
    before do
      @session = Capybara::Session.new(:terminus, TestApp)
      select_browser
    end

    after do
      select_browser
      Terminus.browser.return_to_dock
    end
    
    it_should_behave_like "session"
    it_should_behave_like "session with headers support"
    it_should_behave_like "session with status code support"
    it_should_behave_like "session with javascript support"
  end
end
