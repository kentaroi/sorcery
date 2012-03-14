class SorceryMailer < ActionMailer::Base
  
  default :from => "notifications@example.com"
  
  def activation_needed_email(user)
    @user = user
    @url  = "http://example.com/login"
    mail(:to => user.email,
         :subject => "Welcome to My Awesome Site")
  end
  
  def activation_success_email(user)
    @user = user
    @url  = "http://example.com/login"
    mail(:to => user.email,
         :subject => "Your account is now activated")
  end
  
  def email_verification_needed_email(user)
    @user = user
    @url  = "http://example.com/login"
    mail(:to => user.pending_email,
         :subject => "Instruction to verify your new email")
  end

  def email_verification_success_email(user)
    @user = user
    @url  = "http://example.com/login"
    mail(:to => user.email,
         :subject => "Your new email is now verified")
  end

  def reset_password_email(user)
    @user = user
    @url  = "http://example.com/login"
    mail(:to => user.email,
         :subject => "Your password has been reset")
  end
end
