module Sorcery
  module Model
    module Submodules
      # This submodule adds the ability to make the user activate his account via email
      # or any other way in which he can recieve an activation code.
      # with the activation code the user may activate his account.
      # When using this submodule, supplying a mailer is mandatory.
      module UserActivation
        def self.included(base)
          base.sorcery_config.class_eval do
            attr_accessor :activation_state_attribute_name,               # the attribute name to hold activation state
                                                                          # (active/pending).
                                                                          
                          :activation_token_attribute_name,               # the attribute name to hold activation code
                                                                          # (sent by email).
                                                                          
                          :activation_token_expires_at_attribute_name,    # the attribute name to hold activation code
                                                                          # expiration date. 
                                                                          
                          :activation_token_expiration_period,            # how many seconds before the activation code
                                                                          # expires. nil for never expires.
                                                                          
                          :user_activation_mailer,                        # your mailer class. Required when
                                                                          # activation_mailer_disabled == false.

                          :activation_mailer_disabled,                    # when true sorcery will not automatically
                                                                          # email activation details and allow you to
                                                                          # manually handle how and when email is sent

                          :activation_needed_email_method_name,           # activation needed email method on your
                                                                          # mailer class.
                                                                          
                          :activation_success_email_method_name,          # activation success email method on your
                                                                          # mailer class.
                                                                          
                          :prevent_non_active_users_to_login,             # do you want to prevent or allow users that
                                                                          # did not activate by email to login?

                          :email_verification_on_change_disabled,         # when true sorcery will not verify email
                                                                          # address on change.

                          :pending_email_attribute_name,                  # the attribute name to hold pending email
                                                                          # address.

                          :email_verification_needed_email_method_name,   # activation needed email method on your
                                                                          # mailer class.

                          :email_verification_success_email_method_name   # activation success email method on your
                                                                          # mailer class.

          end
          
          base.sorcery_config.instance_eval do
            @defaults.merge!(:@activation_state_attribute_name              => :activation_state,
                             :@activation_token_attribute_name              => :activation_token,
                             :@activation_token_expires_at_attribute_name   => :activation_token_expires_at,
                             :@activation_token_expiration_period           => nil,
                             :@user_activation_mailer                       => nil,
                             :@activation_mailer_disabled                   => false,
                             :@activation_needed_email_method_name          => :activation_needed_email,
                             :@activation_success_email_method_name         => :activation_success_email,
                             :@prevent_non_active_users_to_login            => true,
                             :@email_verification_on_change_disabled        => true,
                             :@pending_email_attribute_name                 => :pending_email,
                             :@email_verification_needed_email_method_name  => :email_verification_needed_email,
                             :@email_verification_success_email_method_name => :email_verification_success_email)
            reset!
          end
          
          base.class_eval do
            # don't setup activation if no password supplied - this user is created automatically
            before_create :setup_activation, :if => Proc.new { |user| user.send(sorcery_config.password_attribute_name).present? }
            # don't send activation needed email if no crypted password created - this user is external (OAuth etc.)
            after_create  :send_activation_needed_email!, :if => Proc.new { |user| !user.external? }
          end
          
          base.sorcery_config.after_config << :validate_mailer_defined
          base.sorcery_config.after_config << :define_user_activation_mongoid_fields if defined?(Mongoid) and base.ancestors.include?(Mongoid::Document)
          if defined?(MongoMapper) and base.ancestors.include?(MongoMapper::Document)
            base.sorcery_config.after_config << :define_user_activation_mongo_mapper_fields
          end
          base.sorcery_config.after_config << :define_methods_for_email_verification
          base.sorcery_config.before_authenticate << :prevent_non_active_login
          
          base.extend(ClassMethods)
          base.send(:include, InstanceMethods)


        end
        
        module ClassMethods
          # Find user by token, also checks for expiration.
          # Returns the user if token found and is valid.
          def load_from_activation_token(token)
            token_attr_name = @sorcery_config.activation_token_attribute_name
            token_expiration_date_attr = @sorcery_config.activation_token_expires_at_attribute_name
            load_from_token(token, token_attr_name, token_expiration_date_attr)
          end

          alias :load_from_email_verification_token :load_from_activation_token

          protected
          
          # This submodule requires the developer to define his own mailer class to be used by it
          # when activation_mailer_disabled is false
          def validate_mailer_defined
            msg = "To use user_activation submodule, you must define a mailer (config.user_activation_mailer = YourMailerClass)."
            raise ArgumentError, msg if @sorcery_config.user_activation_mailer == nil and @sorcery_config.activation_mailer_disabled == false
          end

          def define_user_activation_mongoid_fields
            self.class_eval do
              field sorcery_config.activation_state_attribute_name,            :type => String
              field sorcery_config.activation_token_attribute_name,            :type => String
              field sorcery_config.activation_token_expires_at_attribute_name, :type => Time
            end
          end

          def define_user_activation_mongo_mapper_fields
            self.class_eval do
              key sorcery_config.activation_state_attribute_name, String
              key sorcery_config.activation_token_attribute_name, String
              key sorcery_config.activation_token_expires_at_attribute_name, Time
            end
          end

          def define_methods_for_email_verification
            return if @sorcery_config.email_verification_on_change_disabled

            if defined?(Mongoid) and self.ancestors.include?(Mongoid::Document)
              define_email_verification_mongoid_field
            end

            if defined?(MongoMapper) and self.ancestors.include?(MongoMapper::Document)
              define_email_verification_mongo_mapper_field
            end

            override_email_attribute_setter_method

            self.class_eval do
              # don't swap back if email address has not been changed
              before_update :swap_back_emails, :if => Proc.new {|user|
                user.send(sorcery_config.pending_email_attribute_name).present? &&
                  user.send("#{sorcery_config.email_attribute_name}_changed?")
              }

              # don't send verification needed email if email address was not changed
              after_update :send_email_verification_needed_email!, :if => Proc.new {|user|
                user.send(sorcery_config.pending_email_attribute_name).present? &&
                  user.previous_changes[sorcery_config.activation_token_attribute_name]
              }

            end
          end

          def define_email_verification_mongoid_field
            self.class_eval do
              field sorcery_config.pending_email_attribute_name, :type => String
            end
          end

          def define_email_verification_mongo_mapper_field
            self.class_eval do
              key sorcery_config.pending_email_attribute_name, String
            end
          end

          def override_email_attribute_setter_method
            method_definition = <<-EOS
              def #{sorcery_config.email_attribute_name}=(new_value)
                if self.send(:#{sorcery_config.activation_state_attribute_name}) == "active"
                  write_attribute(:#{sorcery_config.pending_email_attribute_name}, read_attribute(:#{sorcery_config.email_attribute_name}))
                  write_attribute(:#{sorcery_config.email_attribute_name}, new_value)
                  setup_email_verification
                else
                  write_attribute(:#{sorcery_config.email_attribute_name}, new_value)
                end
              end
            EOS
            self.class_eval method_definition, __FILE__, __LINE__
          end
        end

        module InstanceMethods
          # clears activation code, sets the user as 'active' and optionaly sends a success email.
          def activate!
            config = sorcery_config
            self.send(:"#{config.activation_token_attribute_name}=", nil)
            self.send(:"#{config.activation_state_attribute_name}=", "active")
            send_activation_success_email! unless self.external?
            save!(:validate => false) # don't run validations
          end

          def verify_email!
            config = sorcery_config
            self.send(:"#{config.activation_token_attribute_name}=", nil)
            write_attribute(config.email_attribute_name, read_attribute(config.pending_email_attribute_name))
            write_attribute(config.pending_email_attribute_name, nil)

            save!
            send_email_verification_success_email!
          end

          protected

          def setup_activation
            config = sorcery_config
            generated_activation_token = TemporaryToken.generate_random_token
            self.send(:"#{config.activation_token_attribute_name}=", generated_activation_token)
            self.send(:"#{config.activation_state_attribute_name}=", "pending")
            self.send(:"#{config.activation_token_expires_at_attribute_name}=", Time.now.in_time_zone + config.activation_token_expiration_period) if config.activation_token_expiration_period
          end

          # called automatically after user initial creation.
          def send_activation_needed_email!
            generic_send_email(:activation_needed_email_method_name, :user_activation_mailer) unless sorcery_config.activation_needed_email_method_name.nil? or sorcery_config.activation_mailer_disabled == true
          end

          def send_activation_success_email!
            generic_send_email(:activation_success_email_method_name, :user_activation_mailer) unless sorcery_config.activation_success_email_method_name.nil? or sorcery_config.activation_mailer_disabled == true
          end
          
          def prevent_non_active_login
            config = sorcery_config
            config.prevent_non_active_users_to_login ? self.send(config.activation_state_attribute_name) == "active" : true
          end

          # reuse activation_token_* fields
          def setup_email_verification
            config = sorcery_config
            generated_verification_token = TemporaryToken.generate_random_token
            self.send(:"#{config.activation_token_attribute_name}=", generated_verification_token)
            self.send(:"#{config.activation_token_expires_at_attribute_name}=", Time.now.in_time_zone + config.activation_token_expiration_period) if config.activation_token_expiration_period
          end

          def swap_back_emails
            config = sorcery_config
            tmp = read_attribute(config.email_attribute_name)
            write_attribute(config.email_attribute_name, read_attribute(config.pending_email_attribute_name))
            write_attribute(config.pending_email_attribute_name, tmp)
          end

          def send_email_verification_needed_email!
            generic_send_email(:email_verification_needed_email_method_name, :user_activation_mailer) unless sorcery_config.email_verification_needed_email_method_name.nil?
          end

          def send_email_verification_success_email!
            generic_send_email(:email_verification_success_email_method_name, :user_activation_mailer) unless sorcery_config.email_verification_success_email_method_name.nil?
          end
        end
      end
    end
  end
end
