# Dev proof for P1: run the real local-Gemma vision path on an image and print the coarse read.
#   mise exec -- bin/rails "vision:observe"                     # default staged fixture
#   mise exec -- bin/rails "vision:observe[path/to/image.jpg]"  # any image
namespace :vision do
  desc "Run VisionClient on an image (proves image -> local Gemma -> coarse observation)"
  task :observe, [ :path ] => :environment do |_t, args|
    path = args[:path] ||
           Rails.root.join("test/fixtures/files/vision/counter_one_person.jpg").to_s
    t0 = Time.current
    obs = VisionClient.observe(path)
    puts "image:       #{path}"
    puts "elapsed:     #{(Time.current - t0).round(2)}s"
    puts "observation: #{obs.inspect}"
    puts obs ? "OK — vision path works." : "nil (Gemma unreachable/unparseable → feature stays inert)"
  end
end
