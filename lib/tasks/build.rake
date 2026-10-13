# frozen_string_literal: true

require 'English'
require 'etc'
require 'shellwords'
require 'tmpdir'

module Build
  extend self

  REGISTRY = 'docker.finagle.org'
  IMAGE = 'tabby'
  DEPLOY_HOST = 'whale'
  DEPLOY_COMMAND = './web-apps/Tabby/run'

  # Short version tag (the first 8 characters of the commit SHA) for a git commit, branch, or tag
  def version_tag(commit)
    sha = `git rev-parse --verify --quiet #{"#{commit}^{commit}".shellescape}`.strip
    $CHILD_STATUS.success? or abort "Unknown git commit, branch, or tag: #{commit}"
    sha[0, 8]
  end

  def podman?
    ENV['PATH'].split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, 'podman')) }
  end

  def docker
    podman? ? %w[podman] : %w[sudo docker]
  end
end

desc "Build the Docker image for a git commit, branch, or tag (default: main)"
task :build, [:commit] => :environment do |_task, args|
  commit = args[:commit] || 'main'
  tag = Build.version_tag(commit)
  jobs = (Etc.nprocessors - 1).clamp(1..)

  puts "Building #{commit} (#{tag}) using #{jobs} cores ..."
  Dir.mktmpdir("#{Build::IMAGE}-build-") do |dir|
    sh "git archive #{commit.shellescape} | tar -x -C #{dir.shellescape}"
    sh(*Build.docker, 'build', '-t', "#{Build::IMAGE}:#{tag}",
       '--build-arg', "GIT_VERSION=#{tag}", '--build-arg', "JOBS=#{jobs}", dir)
  end
end

desc "Build and push the Docker image for a git commit, branch, or tag (default: main) to the registry"
task :push, [:commit] => :build do |_task, args|
  commit = args[:commit] || 'main'
  local = "#{Build::IMAGE}:#{Build.version_tag(commit)}"
  remote = "#{Build::REGISTRY}/#{local}"

  if Build.podman?
    sh 'podman', 'push', local, remote
  else
    sh 'sudo', 'docker', 'tag', local, remote
    sh 'sudo', 'docker', 'push', remote
  end
end

desc "Deploy the pushed Docker image for a git commit, branch, or tag to production"
task :deploy, [:commit] => :push do |_task, args|
  commit = args[:commit] || 'main'
  tag = Build.version_tag(commit)

  puts "Deploying #{commit} (#{tag}) to production ..."
  sh 'ssh', Build::DEPLOY_HOST, Build::DEPLOY_COMMAND, tag
end
