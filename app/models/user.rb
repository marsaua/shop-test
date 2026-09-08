class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { user: 0, admin: 1 }, default: :user

  has_one :cart, dependent: :destroy

  after_create :create_default_cart

  private

  def create_default_cart
    create_cart!
  end
end
