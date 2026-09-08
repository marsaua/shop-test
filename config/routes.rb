Rails.application.routes.draw do
  devise_for :users

  root "products#index"

  resources :products
  resource :cart, only: [:show]
  resources :cart_items, only: [:create, :update, :destroy]
  resource :checkout, only: [:new, :create]
  resources :orders, only: [:index, :show]

  get "up" => "rails/health#show", as: :rails_health_check
end
