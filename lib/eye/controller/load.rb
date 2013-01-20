module Eye::Controller::Load

  include Eye::Dsl::Validate

  def syntax(filename = '')
    parse_config(filename).first
  end

  # filename is a path, or folder, or mask
  def load(filename = '')
    mask = if File.directory?(filename)
      File.join filename, '{*.eye}'
    else
      filename
    end

    debug "load: globbing mask #{mask}"
    configs = []

    Dir[mask].each do |config_path|
      info "load: config #{config_path}"

      res, cfg = parse_config(config_path)
      configs << cfg

      return res if res[:error]
    end

    return {:error => true, :message => "config file '#{mask}' not found!"} if configs.blank?

    new_cfg = @current_config
    configs.each{|cfg| new_cfg = merge_configs(new_cfg, cfg) }

    begin
      validate(new_cfg)
    rescue Eye::Dsl::Error => ex
      error "load: final merged config not validated: '#{ex.message}'"
      return {:error => true, :message => ex.message}
    end

    load_config(new_cfg)

    GC.start
    {:error => false}
  end

private

  # return: result, config
  def parse_config(filename = '', &block)
    unless File.exists?(filename)
      error "load: config file '#{filename}' not found!"
      return [{:error => true, :message => "config file '#{filename}' not found!"}]
    end

    cfg = Eye::Dsl.load(nil, filename)
    validate( merge_configs(@current_config, cfg) )

    [{:error => false}, cfg]

  rescue Eye::Dsl::Error, Exception, NoMethodError => ex
    error "load: config error <#{filename}>: #{ex.message}"

    # filter backtrace for user output
    bt = (ex.backtrace || []).reject{|line| line.to_s =~ %r[/lib/eye/] || line.to_s =~ %r[lib/celluloid] || line.to_s =~ %r[internal:prelude] } 
    error bt.join("\n")

    [{:error => true, :message => ex.message, :backtrace => bt}]
  end

  def load_config(new_config)
    load_options
    create_objects(new_config)
    @current_config = new_config
  end

  def merge_configs(old_config, new_config)
    old_config.merge(new_config)
  end

  # load global config options
  def load_options
    opts = Eye.parsed_options
    return if opts.blank?

    if opts[:logger]
      # do not apply logger, if in stdout state
      unless Eye::Logger.dev == 'stdout' || Eye::Logger.dev == 'stderr'
        Eye::Logger.link_logger(opts[:logger])
      end
      
      Eye::Logger.log_level = opts[:logger_level] if opts[:logger_level]
    end

    # clear parsed options, because we already apply them
    Eye.parsed_options = {}
  end

  # create objects as diff, from configs
  def create_objects(new_config)
    debug 'create objects'
    new_config.each do |app_name, app_cfg|
      update_or_create_application(app_name, app_cfg.clone)
    end
  end

  def update_or_create_application(app_name, app_config)
    @old_groups = {}
    @old_processes = {}

    app = @applications.detect{|c| c.name == app_name}

    if app
      app.groups.each do |group|
        @old_groups[group.name] = group
        group.processes.each do |proc|
          @old_processes[proc.name] = proc
        end
      end

      @applications.delete(app)

      debug "update app #{app_name}"
    else
      debug "create app #{app_name}"
    end

    app = Eye::Application.new(app_name, app_config)
    @applications << app

    new_groups = app_config.delete(:groups)
    new_groups.each do |group_name, group_cfg|
      group = update_or_create_group(group_name, group_cfg.clone.merge(:application => app_name))
      app.add_group(group)
    end

    # now, need to clear @old_groups, and @old_processes    
    @old_groups.each{|_, group| group.clear; group.send_command(:delete) }
    @old_processes.each{|_, process| process.send_command(:delete) if process.alive? }

    app
  end

  def update_or_create_group(group_name, group_config)
    group = if @old_groups[group_name]
      debug "update group #{group_name}"
      group = @old_groups.delete(group_name)
      group.schedule :update_config, group_config
      group.clear
      group
    else
      debug "create group #{group_name}"
      Eye::Group.new(group_name, group_config)
    end

    processes = group_config.delete(:processes)
    processes.each do |process_name, process_cfg|
      process = update_or_create_process(process_name, process_cfg)
      group.add_process(process)
    end

    group
  end

  def update_or_create_process(process_name, process_cfg)
    if @old_processes[process_name]
      debug "update process #{process_name}"
      process = @old_processes.delete(process_name)
      process.schedule :update_config, process_cfg
      process      
    else
      debug "create process #{process_name}"
      process = Eye::Process.new(process_cfg)
      process.schedule :monitor
      process
    end
  end

end