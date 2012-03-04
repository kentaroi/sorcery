module Sorcery
  module Model
    module Submodules
      # This submodule adds the ability to verify email address on change.
      # with the email verification code the user may verify his new email address.
      # When using this submodule, supplying a mailer is mandatory.
      module UserActivation
        def self.included(base)
          base.sorcery_config.class_eval do
            attr_accessor :pending_email_attribute_name,                        # the attribute name to hold pending new email address

                          :email_verification_token_attribute_name,             # the attribute name to hold verification code
                                                                                # (sent by email).

                          :email_verification_token_expires_at_attribute_name,  # the attribute name to hold verification code
                                                                                # expiration date. 

                          :email_verification_token_expiration_period,          # how many seconds before the verification code
                                                                                # expires. nil for never expires.

                          :email_verification_mailer,                           # your mailer class. Required when
                                                                                # email_verification_mailer_disabled == false.

                          :email_verification_mailer_disabled,                  # when true sorcery will not automatically
                                                                                # email activation details and allow you to
                                                                                # manually handle how and when email is sent

                          :email_verification_needed_email_method_name,         # email verification needed email method on your
                                                                                # mailer class.

                          :email_verification_success_email_method_name,        # email verification success email method on your
                                                                                # mailer class.
          end

          base.sorcery_config.instance_eval do
            @defaults.merge!(:@email_verification_token_attribute_name             => nil,
                             :@email_verification_token_expires_at_attribute_name  => nil,
                             :@email_verification_token_expiration_period          => nil,
                             :@email_verification_mailer                           => nil,
                             :@email_verification_mailer_disabled                  => false,
                             :@email_verification_needed_email_method_name         => :email_verification_needed_email,
                             :@email_verification_success_email_method_name        => :email_verification_success_email)
            reset!
          end

          base.class_eval do
            # don't setup activation if no password supplied - this user is created automatically
            before_update :setup_email_verification, :if => Proc.new { |user|
              user.send(sorcery_config.pending_email_attribute_name).present? &&
              user.send("#{sorcery_config.email_attribute_name}_changed?")
            }

            # don't swap back if email address has not been changed
            after_validation :swap_back_emails, :if => Proc.new {|user|
              user.send(sorcery_config.pending_email_attribute_name).present? &&
              user.send("#{sorcery_config.email_attribute_name}_changed?")
            }

            # don't send verification needed email if email address was not changed
            after_update :send_email_verification_needed_email!, :if => Proc.new {|user|
              !user.send(sorcery_config.email_verification_mailer_disabled) &&
              user.previous_changes[sorcery_config.pending_email_attribute_name]
            }
          end


          base.sorcery_config.after_config << :copy_user_activation_config_to_email_verification_config_if_nil
          base.sorcery_config.after_config << :validate_mailer_defined

          if defined?(Mongoid) and base.ancestors.include?(Mongoid::Document)
            base.sorcery_config.after_config << :define_email_verification_mongoid_fields
          end

          if defined?(MongoMapper) and base.ancestors.include?(MongoMapper::Document)
            base.sorcery_config.after_config << :define_email_verification_mongo_mapper_fields
          end

          base.sorcery_config.after_config << :override_email_attribute_setter_method


          base.extend(ClassMethods)
          base.send(:include, InstanceMethods)
        end

        module ClassMethods
          # Find user by token, also checks for expiration.
          # Returns the user if token found and is valid.
          def load_from_email_verification_token(token)
            token_attr_name = @sorcery_config.email_verification_token_attribute_name
            token_expiration_date_attr = @sorcery_config.email_verification_token_expires_at_attribute_name
            load_from_token(token, token_attr_name, token_expiration_date_attr)
          end

          protected

          def copy_user_activation_config_to_email_verification_config_if_nil
            unless @sorcery_config.email_verification_token_attribute_name
              @sorcery.email_verification_token_attribute_name = @sorcery_config.user_activation_token_attribute_name
            end

            unless @sorcery_config.email_verification_token_expires_at_attribute_name
              @sorcery.email_verification_token_expires_at_attribute_name = @sorcery_config.user_activation_token_expires_at_attribute_name
            end

            unless @sorcery_config.email_verification_token_expiration_period
              @sorcery.email_verification_token_expiration_period = @sorcery_config.user_activation_token_expiration_period
            end
          end

          # This submodule requires the developer to define his own mailer class to be used by it
          # when email_verification_mailer_disabled is false
          def validate_mailer_defined
            msg = "To use user_activation submodule, you must define a mailer (config.user_activation_mailer = YourMailerClass)."
            raise ArgumentError, msg if @sorcery_config.email_verification_mailer == nil and @sorcery_config.email_verification_mailer_disabled == false
          end

          def define_email_verification_mongoid_fields
            self.class_eval do
              field sorcery_config.pending_email_attribute_name,                       :type => String
              field sorcery_config.email_verification_token_attribute_name,            :type => String if sorcery_config.email_verification_token_attribute_name != sorcery_config.activation_token_attribute_name
              field sorcery_config.email_verification_token_expires_at_attribute_name, :type => Time   if sorcery_config.email_verification_token_expires_at_attribute_name != sorcery_config.activation_token_expires_at_attribute_name
            end
          end

          def define_email_verification_mongo_mapper_fields
            self.class_eval do
              key sorcery_config.pending_email_attribute_name, String
              key sorcery_config.email_verification_token_attribute_name, String          if sorcery_config.email_verification_token_attribute_name != sorcery_config.activation_token_attribute_name
              key sorcery_config.email_verification_token_expires_at_attribute_name, Time if sorcery_config.email_verification_token_expires_at_attribute_name != sorcery_config.activation_token_expires_at_attribute_name
            end
          end

          # Evacuate email address to pending email field and set new email address to email field until validation finished
          def override_email_attribute_setter_method
            method_definition = <<-EOS
              def #{sorcery_config.email_attribute_name}=}(new_value)
                write_attribute('#{sorcery_config.pending_email_attribute_name}',read_attribute('#{sorcery_config.email_attribute_name}))
                write_attribute('#{sorcery_config.email_attribute_name}',new_value)
              end
            EOS

            begin
              self.class_eval method_definition, __FILE__, __LINE__
            rescue SyntaxError => err
              if logger
                logger.warn "Exception occurred during email setter method compilation."
                logger.warn err.message
              end
            end
          end
        end

        module InstanceMethods
          # clears email verification code, sets email as pending email, clears pending email and optionaly sends a success email.
          def verify_email!
            config = sorcery_config
            self.send(:"#{config.email_verification_token_attribute_name}=", nil)
            write_attribute('#{config.email_attribute_name}', self.send(config.pending_email_attribute_name))
            self.send(:"#{config.pending_email_attribute_name}=", nil)

            unless valid?
              raise_validation_error_on_email! if errors.messages[config.email_attribute_name]
              @errors = nil
            end

            save!(:validate => false) # don't run validations
            send_verification_success_email!
          end

          protected

          def setup_email_verification
            config = sorcery_config
            generated_verification_token = TemporaryToken.generate_random_token
            self.send(:"#{config.email_verification_attribute_name}=", generated_activation_token)
            if config.email_verification_token_expiration_period
              self.send(:"#{config.email_verification_token_expires_at_attribute_name}=",
                        Time.now.in_time_zone + config.email_verification_token_expiration_period)
            end
          end

          def swap_back_emails
            config = sorcery_config
            tmp = self.send(config.email_attribute_name)
            write_attribute("#{sorcery_config.email_attribute_name}", self.send(sorcery_config.pending_email_attribute_name))
            write_attribute("#{sorcery_config.pending_email_attribute_name}", tmp)
          end

          def raise_validation_failed_on_email!
            if defined?(ActiveRecord) and self.class.ancestors.include?(ActiveRecord::Base)
              raise ActiveRecord::RecordInvalid, "Validation failed #{errors.messages[config.email_attribute_name]}"
            elsif defined?(Mongoid) and self.class.ancestors.include?(Mongoid::Document)
              raise Errors::Validations, "Validation failed #{errors.messages[config.email_attribute_name]}"
            elsif defined?(MongoMapper) and self.class.ancestors.include?(MongoMapper::Document)
              raise MongMapper::DocumentNotValid, "Validation failed #{errors.messages[config.email_attribute_name]}"
            else
              raise Errors, "Validation failed #{errors.messages[config.email_attribute_name]}"
            end
          end

          # called automatically after user's email field updated
          def send_email_verification_needed_email!
            generic_send_email(:email_verification_needed_email_method_name, :email_verification_mailer) unless sorcery_config.email_verification_needed_email_method_name.nil? or sorcery_config.email_verification_mailer_disabled == true
          end

          def send_email_verification_success_email!
            generic_send_email(:email_verification_success_email_method_name, :email_verification_mailer) unless sorcery_config.email_verification_success_email_method_name.nil? or sorcery_config.email_verification_mailer_disabled == true
          end

        end
      end
    end
  end
end
