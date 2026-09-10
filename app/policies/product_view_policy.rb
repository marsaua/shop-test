class ProductViewPolicy < ApplicationPolicy
  def create?
    owner?
  end

  def index?
    user.present?
  end

  private

  def owner?
    user.present? && record.user_id == user.id
  end
end
