require 'rails_helper'

describe ApplicationController, type: :controller do
  describe 'authenticate_connect_app_request helper' do
    before do

    end

    context 'new appinstance' do
      it 'creates appinstance' do
        get :index
        response.status.should == 500
      end
    end
  end
end
