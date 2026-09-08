require "rails_helper"

RSpec.describe User, type: :model do
  it { is_expected.to define_enum_for(:role).with_values(user: 0, admin: 1) }

  it "defaults to the user role" do
    expect(create(:user).role).to eq("user")
  end

  it "is not an admin by default" do
    expect(create(:user)).not_to be_admin
  end

  it "is an admin with the :admin trait" do
    expect(create(:user, :admin)).to be_admin
  end

  it { is_expected.to have_one(:cart).dependent(:destroy) }
  it { is_expected.to have_many(:orders) }

  it "creates a cart automatically when the user is created" do
    expect(create(:user).cart).to be_present
  end
end
