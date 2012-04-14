require File.expand_path('../spec_helper', __FILE__)

describe Capybara::Driver::Terminus do
  before do
    @driver = Capybara::Driver::Terminus.new(TestApp)
    select_browser
  end

  after do
    Terminus.browser.return_to_dock
  end
  
  it_should_behave_like "driver"
  it_should_behave_like "driver with header support"
  it_should_behave_like "driver with status code support"
  it_should_behave_like "driver with javascript support"
  it_should_behave_like "driver with resynchronization support"
  it_should_behave_like "driver with frame support"
  it_should_behave_like "driver with support for window switching"
  it_should_behave_like "driver with cookies support"
  it_should_behave_like "driver with infinite redirect detection"
end
