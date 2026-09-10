Rails.application.routes.draw do
  devise_for :users

  root "products#index"

  resources :products do
    resource :favorite, only: [ :create, :destroy ]
    resource :product_view, only: [ :create ]

    collection do
      get :by_ids
    end
  end
  resource :cart, only: [ :show ]
  resources :cart_items, only: [ :create, :update, :destroy ]
  resource :checkout, only: [ :new, :create ]
  resources :orders, only: [ :index, :show ]
  resources :favorites, only: [ :index ] do
    post :merge, on: :collection
  end
  resources :product_views, only: [ :index ]
  resource :comparison, only: [ :show ], controller: "comparison"

  get "up" => "rails/health#show", as: :rails_health_check
end
