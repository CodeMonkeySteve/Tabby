Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # authentication
  get 'signin' => 'users#new', as: 'login'
  get 'auth/:provider/callback' => 'users#login'
  get 'signout' => 'users#logout', as: 'logout'
  get 'settings' => 'users#edit', as: 'settings'
  patch 'settings' => 'users#update'
  get 'dashboard' => 'users#dashboard', as: 'dashboard'

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  # get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker

  resources :playlists, path: '/pl'

  resources 'songs', path: '/s' do
    member do
      get 'score' => 'songs#score'
      get 'audio' => 'songs#audio'
      patch 'sync_points' => 'songs#sync_points'
      patch 'find_cover' => 'songs#find_cover'
      patch 'remove_cover' => 'songs#remove_cover'
      post 'playlist' => 'songs#playlist'
      post 'track' => 'songs#track_history'
    end

    # the current user's note
    resource :note, only: :update, controller: 'song_notes'
  end
  get 'p/:id' => 'songs#player', as: 'player'

  root to: 'users#dashboard'
  mount ActionDispatch::Static.new(Rails.application, Rails.root.join('storage/files').to_s), at: '/files'
end
