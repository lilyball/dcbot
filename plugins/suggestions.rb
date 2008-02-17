class Suggestion < ActiveRecord::Base
end
Suggestion.table_name = "suggestions"

class SuggestionPlugin < PluginBase
  def self.cmd_suggest(socket, sender, isprivate, args)
    args.strip!
    if args.blank? then
      HelpPlugin.send_usage(socket, sender, "suggest")
    else
      suggestion = Suggestion.new(:suggestion => args, :submitter => sender)
      suggestion.save!
      socket.sendPublicMessage("#{sender} has suggested \"#{args}\"")
      if isprivate then
        socket.sendPrivateMessage(sender, "Suggestion ##{suggestion.id} submitted for \"#{args}\"")
      end
    end
  end
  
  def self.cmd_suggest_help
    ["Suggestion", "Submits a suggestion for improvement to RequestBot, e.g. #{CMD_PREFIX}suggest Implement a Trivia bot"]
  end
  
  def self.cmd_suggestions(socket, sender, isprivate, args)
    suggestions = Suggestion.find(:all)
    if suggestions.blank? then
      socket.sendPrivateMessage(sender, "No submitted suggestions")
    else
      completedSuggestions = suggestions.select { |req| req.completed? }
      openSuggestions = suggestions.reject { |req| req.completed? }
      format = "  #%-4d \"%s\" by %s"
      socket.sendPrivateMessage(sender, "Completed suggestions:") unless completedSuggestions.blank?
      completedSuggestions.each do |suggestion|
        message = format % [suggestion.id, suggestion.suggestion, suggestion.submitter]
        socket.sendPrivateMessage(sender, message)
      end
      socket.sendPrivateMessage(sender, "Suggestions:") unless openSuggestions.blank?
      openSuggestions.each do |suggestion|
        message = format % [suggestion.id, suggestion.suggestion, suggestion.submitter]
        socket.sendPrivateMessage(sender, message)
      end
    end
  end
  
  def self.cmd_suggestions_help
    ["", "Lists the submitted suggestions"]
  end
  
  def self.cmd_del_suggestion(socket, sender, isprivate, args)
    if isprivate
      begin
        suggestion = Suggestion.find(args.to_i)
        if suggestion.completed? then
          socket.sendPrivateMessage(sender, "Suggestion ##{suggestion.id} could not be deleted as it has already been completed")
        elsif suggestion.submitter == sender then
          suggestion.destroy
          socket.sendPrivateMessage(sender, "Suggestion ##{suggestion.id} has been deleted")
          socket.sendPublicMessage("Suggestion ##{suggestion.id} \"#{suggestion.suggestion}\" has been deleted by #{sender}")
        else
          socket.sendPrivateMessage(sender, "You do not have permission to delete suggestion ##{suggestion.id}")
        end
      rescue ActiveRecord::RecordNotFound
        socket.sendPrivateMessage(sender, "That suggestion could not be found")
      end
    else
      socket.sendPrivateMessage(sender, "That command must be executed in private chat only")
    end
  end
  
  def self.cmd_del_suggestion_help
    ["SuggestionNum", "Deletes a suggestion you submitted, e.g. #{CMD_PREFIX}del_suggestion #23"]
  end
end
