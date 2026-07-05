Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "console#index"
  get  "console",      to: "console#index", as: :console
  post "console/demo", to: "console#demo",  as: :console_demo
  post "console/tick", to: "console#tick",  as: :console_tick

  # Camera-vision capstone: browser posts a downscaled frame; server derives a coarse
  # observation via local Gemma and discards the frame. See docs/vision-capstone-spec.md.
  post "vision/observations", to: "vision_observations#create", as: :vision_observations
  # Deterministic demo: seed a camera scenario (waiting|busy|left) without a live camera.
  post "vision/simulate", to: "vision_observations#simulate", as: :vision_simulate

  resources :advisories, only: [] do
    member do
      patch :accept
      patch :override
    end
  end
end
