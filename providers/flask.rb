#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: application_python
# Provider:: flask
#
# Copyright:: 2011, Opscode, Inc <legal@opscode.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'tmpdir'

include Chef::DSL::IncludeRecipe

action :before_compile do
  include_recipe 'python'

  new_resource.symlink_before_migrate.update({
    new_resource.local_settings_base => new_resource.local_settings_file,
  })
end

action :before_deploy do

  install_packages

  created_settings_file

end

action :before_migrate do

  if new_resource.requirements.nil?
    # look for requirements.txt files in common locations
    [
      ::File.join(new_resource.release_path, "requirements", "#{node.chef_environment}.txt"),
      ::File.join(new_resource.release_path, "requirements.txt")
    ].each do |path|
      if ::File.exists?(path)
        new_resource.requirements path
        break
      end
    end
  end
  if new_resource.requirements
    Chef::Log.info("Installing using requirements file: #{new_resource.requirements}")
    pip_cmd = ::File.join(new_resource.virtualenv, 'bin', 'pip')
    execute "#{pip_cmd} install --source=#{Dir.tmpdir} -r #{new_resource.requirements}" do
      cwd new_resource.release_path
      # seems that if we don't set the HOME env var pip tries to log to /root/.pip, which fails due to permissions
      # setting HOME also enables us to control pip behavior on per-project basis by dropping off a pip.conf file there
      # GIT_SSH allow us to reuse the deployment key used to clone the main
      # repository to clone any private requirements
      if new_resource.deploy_key
        environment 'HOME' => ::File.join(new_resource.path,'shared'), 'GIT_SSH' => "#{new_resource.path}/deploy-ssh-wrapper"
      else
        environment 'HOME' => ::File.join(new_resource.path,'shared')
      end
      user new_resource.owner
      group new_resource.group
    end
  else
    Chef::Log.debug("No requirements file found")
  end

end

action :before_symlink do
end

action :before_restart do
end

action :after_restart do
end

protected

def install_packages
  python_virtualenv new_resource.virtualenv do
    path new_resource.virtualenv
    owner new_resource.owner
    group new_resource.group
    action :create
  end

  new_resource.packages.each do |name, ver|
    python_pip name do
      version ver if ver && ver.length > 0
      virtualenv new_resource.virtualenv
      user new_resource.owner
      group new_resource.group
      action :install
    end
  end

def created_settings_file

  template "#{new_resource.path}/shared/#{new_resource.local_settings_base}" do
    source new_resource.settings_template || "settings.py.erb"
    cookbook new_resource.settings_template ? new_resource.cookbook_name.to_s : "application_python"
    owner new_resource.owner
    group new_resource.group
    mode "644"
    variables new_resource.settings.clone
    variables.update :flask => new_resource, :debug => new_resource.debug
  end
end
end
