shared_examples_for "rails_3_activation_model" do
  # ----------------- PLUGIN CONFIGURATION -----------------------
  describe User, "loaded plugin configuration" do
    before(:all) do
      sorcery_reload!([:user_activation], :user_activation_mailer => ::SorceryMailer)
    end
  
    after(:each) do
      User.sorcery_config.reset!
      sorcery_reload!([:user_activation], :user_activation_mailer => ::SorceryMailer)
    end
    
    it "should enable configuration option 'activation_state_attribute_name'" do
      sorcery_model_property_set(:activation_state_attribute_name, :status)
      User.sorcery_config.activation_state_attribute_name.should equal(:status)    
    end
    
    it "should enable configuration option 'activation_token_attribute_name'" do
      sorcery_model_property_set(:activation_token_attribute_name, :code)
      User.sorcery_config.activation_token_attribute_name.should equal(:code)    
    end
    
    it "should enable configuration option 'user_activation_mailer'" do
      sorcery_model_property_set(:user_activation_mailer, TestMailer)
      User.sorcery_config.user_activation_mailer.should equal(TestMailer)    
    end
    
    it "should enable configuration option 'activation_needed_email_method_name'" do
      sorcery_model_property_set(:activation_needed_email_method_name, :my_activation_email)
      User.sorcery_config.activation_needed_email_method_name.should equal(:my_activation_email)
    end
    
    it "should enable configuration option 'activation_success_email_method_name'" do
      sorcery_model_property_set(:activation_success_email_method_name, :my_activation_email)
      User.sorcery_config.activation_success_email_method_name.should equal(:my_activation_email)
    end

    it "should enable configuration option 'activation_mailer_disabled'" do
      sorcery_model_property_set(:activation_mailer_disabled, :my_activation_mailer_disabled)
      User.sorcery_config.activation_mailer_disabled.should equal(:my_activation_mailer_disabled)
    end
    
    it "if mailer is nil and mailer is enabled, throw exception!" do
      expect{sorcery_reload!([:user_activation], :activation_mailer_disabled => false)}.to raise_error(ArgumentError)
    end

    it "if mailer is disabled and mailer is nil, do NOT throw exception" do
      expect{sorcery_reload!([:user_activation], :activation_mailer_disabled => true)}.to_not raise_error
    end

    it "should enable configuration option 'email_verification_on_change_disabled'" do
      sorcery_model_property_set(:email_verification_on_change_disabled, :my_email_verification_disabled)
      User.sorcery_config.email_verification_on_change_disabled.should equal(:my_email_verification_disabled)
    end

    it "should enable configuration option 'pending_email_attribute_name'" do
      sorcery_model_property_set(:pending_email_attribute_name, :my_pending_email)
      User.sorcery_config.pending_email_attribute_name.should equal(:my_pending_email)
    end

    it "should enable configuration option 'email_verification_needed_email_method_name'" do
      sorcery_model_property_set(:email_verification_needed_email_method_name, :my_verification_email)
      User.sorcery_config.email_verification_needed_email_method_name.should equal(:my_verification_email)
    end

    it "should enable configuration option 'email_verification_success_email_method_name'" do
      sorcery_model_property_set(:email_verification_success_email_method_name, :my_verification_email)
      User.sorcery_config.email_verification_success_email_method_name.should equal(:my_verification_email)
    end
  end

  # ----------------- ACTIVATION PROCESS -----------------------
  describe User, "activation process" do
    before(:all) do
      sorcery_reload!([:user_activation], :user_activation_mailer => ::SorceryMailer)
    end
    
    before(:each) do
      create_new_user
    end
    
    it "should initialize user state to 'pending'" do
      @user.activation_state.should == "pending"
    end
    
    specify { @user.should respond_to(:activate!) }
    
    it "should clear activation code and change state to 'active' on activation" do
      activation_token = @user.activation_token
      @user.activate!
      @user2 = User.find(@user.id) # go to db to make sure it was saved and not just in memory
      @user2.activation_token.should be_nil
      @user2.activation_state.should == "active"
      User.find_by_activation_token(activation_token).should be_nil
    end


    context "mailer is enabled" do
      it "should send the user an activation email" do
        old_size = ActionMailer::Base.deliveries.size
        create_new_user
        ActionMailer::Base.deliveries.size.should == old_size + 1
      end

      it "subsequent saves do not send activation email" do
        old_size = ActionMailer::Base.deliveries.size
        @user.username = "Shauli"
        @user.save!
        ActionMailer::Base.deliveries.size.should == old_size
      end

      it "should send the user an activation success email on successful activation" do
        old_size = ActionMailer::Base.deliveries.size
        @user.activate!
        ActionMailer::Base.deliveries.size.should == old_size + 1
      end

      it "subsequent saves do not send activation success email" do
        @user.activate!
        old_size = ActionMailer::Base.deliveries.size
        @user.username = "Shauli"
        @user.save!
        ActionMailer::Base.deliveries.size.should == old_size
      end

      it "activation needed email is optional" do
        sorcery_model_property_set(:activation_needed_email_method_name, nil)
        old_size = ActionMailer::Base.deliveries.size
        create_new_user
        ActionMailer::Base.deliveries.size.should == old_size
      end

      it "activation success email is optional" do
        sorcery_model_property_set(:activation_success_email_method_name, nil)
        old_size = ActionMailer::Base.deliveries.size
        @user.activate!
        ActionMailer::Base.deliveries.size.should == old_size
      end
    end

    context "mailer has been disabled" do
      before(:each) do
        sorcery_reload!([:user_activation], :activation_mailer_disabled => true, :user_activation_mailer => ::SorceryMailer)
      end

      it "should not send the user an activation email" do
        old_size = ActionMailer::Base.deliveries.size
        create_new_user
        ActionMailer::Base.deliveries.size.should == old_size
      end

      it "should not send the user an activation success email on successful activation" do
        old_size = ActionMailer::Base.deliveries.size
        @user.activate!
        ActionMailer::Base.deliveries.size.should == old_size
      end
    end
  end

  describe User, "prevent non-active login feature" do
    before(:all) do
      sorcery_reload!([:user_activation], :user_activation_mailer => ::SorceryMailer)
    end

    before(:each) do
      User.delete_all
      create_new_user
    end

    it "should not allow a non-active user to authenticate" do
      User.authenticate(@user.username,'secret').should be_false
    end
    
    it "should allow a non-active user to authenticate if configured so" do
      sorcery_model_property_set(:prevent_non_active_users_to_login, false)
      User.authenticate(@user.username,'secret').should be_true
    end
  end
  
  describe User, "load_from_activation_token" do
    before(:all) do
      sorcery_reload!([:user_activation], :user_activation_mailer => ::SorceryMailer)
    end
    
    after(:each) do
      Timecop.return
    end
    
    it "load_from_activation_token should return user when token is found" do
      create_new_user
      User.load_from_activation_token(@user.activation_token).should == @user
    end
    
    it "load_from_activation_token should NOT return user when token is NOT found" do
      create_new_user
      User.load_from_activation_token("a").should == nil
    end
    
    it "load_from_activation_token should return user when token is found and not expired" do
      sorcery_model_property_set(:activation_token_expiration_period, 500)
      create_new_user
      User.load_from_activation_token(@user.activation_token).should == @user
    end
    
    it "load_from_activation_token should NOT return user when token is found and expired" do
      sorcery_model_property_set(:activation_token_expiration_period, 0.1)
      create_new_user
      Timecop.travel(Time.now.in_time_zone+0.5)
      User.load_from_activation_token(@user.activation_token).should == nil
    end
    
    it "load_from_activation_token should return nil if token is blank" do
      User.load_from_activation_token(nil).should == nil
      User.load_from_activation_token("").should == nil
    end
    
    it "load_from_activation_token should always be valid if expiration period is nil" do
      sorcery_model_property_set(:activation_token_expiration_period, nil)
      create_new_user
      User.load_from_activation_token(@user.activation_token).should == @user
    end
  end

  # ----------------- EMAIL VERIFICATION PROCESS ---------------
  describe User, "email verification process" do
    context "email verification on change has been enabled" do
      before(:all) do
        sorcery_reload!([:user_activation], :email_verification_on_change_disabled => false, :user_activation_mailer => ::SorceryMailer)
      end
      before(:each) do
        create_new_user
      end

      specify { @user.should respond_to(:verify_email!) }

      context "when user has not been activated" do
        before do
          @old_email = @user.email
          @new_email = 'new@example.com'
          @user.email = @new_email
        end

        it "should behave normal setter method" do
          @user.email.should == @new_email
          @user.pending_email.should be_nil
          @user.activation_token.should be_nil
        end

        context "when User#save" do
          before do
            @old_size = ActionMailer::Base.deliveries.size
            @user.save
          end

          it "should not swap back email addresses and hold new email address in email attribute and should not send the user a verification email" do
            @user.email.should == @new_email
            @user.pending_email.should be_nil
            @user.activation_token.should be_nil
            ActionMailer::Base.deliveries.size.should == @old_size
          end

          context "when call verify_email!" do
            before do
              @email = @user.email
              @pending_email = @user.pending_email
              @activation_token = @user.activation_token
              @old_size = ActionMailer::Base.deliveries.size
              @user.verify_email!
            end

            it "should not do anything" do
              @user.email.should == @email
              @user.pending_email.should == @pending_email
              @user.activation_token.should == @activation_token
              ActionMailer::Base deliveries.size.should == @old_size
            end
          end
        end
      end

      context "when user has been activated" do
        before(:each) do
          @user.activation_state = 'active'
          @user.save
        end

        context "when set new email address" do
          before do
            @old_email = @user.email
            @new_email = 'new@example.com'
            @user.email = @new_email
          end

          it "should copy current email address to pending_email attribute and hold new email address in email attribute until User#save" do
            @user.email.should == @new_email
            @user.pending_email.should == @old_email
          end

          context "when User#save" do
            before do
              @old_size = ActionMailer::Base.deliveries.size
              @user.save
            end

            it "should swap back email addresses and hold new email address in pending_email attribute and should send the user a verification email" do
              @user.email.should == @old_email
              @user.pending_email.should == @new_email
              @user.activation_token.should_not be_nil
              ActionMailer::Base.deliveries.size.should == @old_size + 1
            end

            context "when verified email successfully" do
              before do
                @old_size = ActionMailer::Base.deliveries.size
                @user.verify_email!
              end

              it "should have new email address, clear pending_email and email verification code and send the user a verification success email" do
                @user2 = User.find(@user.id) # go to db to make sure it was saved and not just in memory
                @user2.email.should == @new_email
                @user2.pending_email.should be_nil
                @user2.activation_token.should be_nil
                ActionMailer::Base deliveries.size.should == @old_size + 1
              end
            end
          end
        end
      end
    end

    context "email verification on change has been disabled" do
      before(:all) do
        sorcery_reload!([:user_activation], :email_verification_on_change_disabled => true, :user_activation_mailer => ::SorceryMailer)
      end
      before(:each) do
        create_new_user
        @user.activation_state = 'active'
        @user.save
      end


      context "when set new email address" do
        before do
          @old_email = @user.email
          @new_email = 'new@example.com'
          @user.email = @new_email
        end

        it "should behave normal setter method" do
          @user.email.should == @new_email
          @user.pending_email.should be_nil
          @user.activation_token.should be_nil
        end

        context "when User#save" do
          before do
            @old_size = ActionMailer::Base.deliveries.size
            @user.save
          end

          it "should not swap back email addresses and hold new email address in email attribute and should not send the user a verification email" do
            @user.email.should == @new_email
            @user.pending_email.should be_nil
            @user.activation_token.should be_nil
            ActionMailer::Base.deliveries.size.should == @old_size
          end
        end
      end
    end
  end
end
