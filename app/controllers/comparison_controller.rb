class ComparisonController < ApplicationController
  # The comparison list is stored entirely client-side (localStorage), so
  # this action just renders the page shell - the same product visibility
  # rule as the products index/by_ids applies (public, no per-record data).
  def show
    authorize Product, :index?
  end
end
