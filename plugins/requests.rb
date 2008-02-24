require 'yaml'

class ::Numeric
  def englishTimeDelta
    oneMinute = 60
    oneHour = oneMinute * 60
    oneDay = oneHour * 24
    oneWeek = oneDay * 7
    if self >= oneWeek then
      divisor = oneWeek
      englishName = "week"
    elsif self >= oneDay then
      divisor = oneDay
      englishName = "day"
    elsif self >= oneHour then
      divisor = oneHour
      englishName = "hour"
    elsif self >= oneMinute then
      divisor = oneMinute
      englishName = "minute"
    else
      divisor = 1
      englishName = "second"
    end
    timeDelta = ((self / divisor.to_f) * 10).round / 10.0
    timeDelta = timeDelta.to_i if timeDelta % 1 == 0
    "#{timeDelta} #{englishName}#{timeDelta == 1.0 ? "" : "s"}"
  end
end

class Request < ActiveRecord::Base
  # currently unused
  def sendErrors(socket, person)
    if request.errors.blank? then
      socket.sendPrivateMessage(sender, "An unknown error occurred while saving the request, please inform FT_[Eridius]")
    elsif request.errors.count == 1 then
      request.errors.each_full do |err| # I can't see any way to just fetch the first error otherwise
        socket.sendPrivateMessage(sender, "An error occurred while saving the request: #{attrib} #{err}")
      end
    else
      socket.sendPrivateMessage(sender, "Errors ocurred while saving the request:")
      request.errors.each_full do |err|
        socket.sendPrivateMessage(sender, "  #{err}")
      end
    end
  end
end
Request.table_name = "requests" # do this because of the anonymous module crap

class RequestPlugin < PluginBase
  TIME_FORMAT = "%a %b %d %H:%M:%S %Z %Y"
  
  def self.send_request_list(hub, user, requests)
    format = "  #%-4d \"%s\" by %s - %s"
    requests.each do |request|
      message = format % [request.id, request.request, request.submitter, request.created_at.strftime(TIME_FORMAT)]
      message << " - claimed by #{request.claimer}" if request.claimer
      hub.sendPrivateMessage(user, message)
    end
  end
  
  # !request
  def self.cmd_request(socket, sender, isprivate, args)
    args.strip!
    if args.blank? then
      HelpPlugin.send_usage(socket, sender, "request")
    else
      request = Request.new(:request => args, :submitter => sender)
      request.save!
      socket.sendPublicMessage("#{sender} has requested ##{request.id} \"#{args}\"")
      if isprivate then
        socket.sendPrivateMessage(sender, "Request ##{request.id} submitted for \"#{args}\"")
      end
    end
  end
  
  def self.cmd_request_help
    ["RequestedItem", "Submits a request for RequestedItem. ex. #{CMD_PREFIX}request The Matrix"]
  end
  
  # !list
  def self.cmd_list(socket, sender, isprivate, args)
    openRequests = Request.find_all_by_filled_at(nil)
    if openRequests.blank? then
      socket.sendPrivateMessage(sender, "No open requests")
    else
      claimedRequests = openRequests.select { |req| req.claimer? }
      unclaimedRequests = openRequests.reject { |req| req.claimer? }
      socket.sendPrivateMessage(sender, "Claimed requests:") unless claimedRequests.blank?
      send_request_list socket, sender, claimedRequests
      socket.sendPrivateMessage(sender, "Unclaimed requests:") unless unclaimedRequests.blank?
      send_request_list socket, sender, unclaimedRequests
    end
  end
  
  def self.cmd_list_help
    [nil, "Lists all open requests"]
  end
  
  # !claim
  def self.cmd_claim(socket, sender, isprivate, args)
    if isprivate
      begin
        request = Request.find(args.to_i)
        if request.filled_at? then
          socket.sendPrivateMessage(sender, "That request has already been filled")
        else
          if request.claimer? and request.claimer != sender then
            socket.sendPrivateMessage(sender, "Overriding previous claim by #{request.claimer}")
            socket.sendPrivateMessage(request.claimer, "#{sender} is overriding your claim on request ##{request.id} - \"#{request.request}\" by #{request.submitter}")
            request.last_claimer = request.claimer
          end
          request.claimer = sender
          request.save!
          socket.sendPrivateMessage(sender, "Request ##{request.id} successfully claimed")
        end
      rescue ActiveRecord::RecordNotFound
        socket.sendPrivateMessage(sender, "That request could not be found")
      end
    else
      socket.sendPrivateMessage(sender, "That command must be executed in private chat only")
    end
  end
  
  def self.cmd_claim_help
    ["RequestNum", "Claims the given request. ex. #{CMD_PREFIX}claim 32"]
  end
  
  # !unclaim
  def self.cmd_unclaim(socket, sender, isprivate, args)
    if isprivate
      begin
        request = Request.find(args.to_i)
        if request.filled_at? then
          socket.sendPrivateMessage(sender, "That request has already been filled")
        else
          if request.claimer? and request.claimer == sender then
            request.claimer = request.last_claimer
            request.last_claimer = nil
            request.save!
            socket.sendPrivateMessage(sender, "Forgetting claim for request ##{request.id}")
            if request.claimer? then
              socket.sendPrivateMessage(request.claimer, "#{sender} has reverted claim of request ##{request.id} back to you")
            end
          elsif request.last_claimer? and request.last_claimer == sender then
            request.last_claimer = nil
            request.save!
            socket.sendPrivateMessage(sender, "Forgetting prior claim for request ##{request.id}")
          else
            socket.sendPrivateMessage(sender, "You are not the claimer for request ##{request.id}")
          end
        end
      rescue ActiveRecord::RecordNotFound
        socket.sendPrivateMessage(sender, "That request could not be found")
      end
    else
      socket.sendPrivateMessage(sender, "That command must be executed in private chat only")
    end
  end
  
  def self.cmd_unclaim_help
    ["RequestNum", "Removes your claim on the given request. ex. #{CMD_PREFIX}unclaim 17"]
  end
  
  # !fill
  def self.cmd_fill(socket, sender, isprivate, args)
    if isprivate
      begin
        request = Request.find(args.to_i)
        if request.filled_at? then
          socket.sendPrivateMessage(sender, "That request has already been filled")
        else
          if request.claimer? and request.claimer != sender then
            claimOverridden = true
            request.last_claimer = request.claimer # fairly useless as filled requests are frozen
          else
            claimOverridden = false
          end
          request.claimer = sender
          request.filled_at = Time.now
          request.save!
          socket.sendPrivateMessage(sender, "Request ##{request.id} filled")
          if claimOverridden then
            socket.sendPrivateMessage(request.last_claimer, "#{request.claimer} has filled your claimed request ##{request.id} - \"#{request.request}\" by #{request.submitter}")
          end
          timeDelta = (request.filled_at - request.created_at).englishTimeDelta
          socket.sendPrivateMessage(request.submitter, "Request ##{request.id} - \"#{request.request}\" has been filled by #{sender} - it took #{timeDelta}")
          socket.sendPublicMessage("#{sender} has filled request ##{request.id} - \"#{request.request}\" by #{request.submitter} - it took #{timeDelta}")
        end
      rescue ActiveRecord::RecordNotFound
        socket.sendPrivateMessage(sender, "That request could not be found")
      end
    else
      socket.sendPrivateMessage(sender, "That command must be executed in private chat only")
    end
  end
  
  def self.cmd_fill_help
    ["RequestNum", "Fills the given request. ex. #{CMD_PREFIX}fill 47"]
  end
  
  # !status
  def self.cmd_status(socket, sender, isprivate, args)
    submittedRequests = Request.find(:all, :conditions => ["submitter = ?", sender])
    claimedRequests = Request.find(:all, :conditions => ["claimer = ? AND filled_at IS NULL", sender])
    if submittedRequests.blank? and claimedRequests.blank? then
      socket.sendPrivateMessage(sender, "No submitted or claimed requests")
    else
      unless submittedRequests.blank?
        socket.sendPrivateMessage(sender, "Submitted requests:")
        submittedRequests.each do |request|
          message = "  #%-4d \"%s\" - %s" % [request.id, request.request, request.created_at.strftime(TIME_FORMAT)]
          if request.filled_at? then
            message << " - filled by #{request.claimer}"
          else
            message << " - claimed by #{request.claimer}" if request.claimer?
          end
          socket.sendPrivateMessage(sender, message)
        end
      end
      unless claimedRequests.blank?
        socket.sendPrivateMessage(sender, "Claimed requests:")
        claimedRequests.each do |request|
          message = "  #%-4d \"%s\" by %s - %s" % [request.id, request.request, request.submitter, request.created_at.strftime(TIME_FORMAT)]
          socket.sendPrivateMessage(sender, message)
        end
      end
    end
  end
  
  def self.cmd_status_help
    [nil, "Displays the status of all of your submitted or claimed requests"]
  end
  
  # !delete
  def self.cmd_delete(socket, sender, isprivate, args)
    if isprivate
      begin
        request = Request.find(args.to_i)
        if request.filled_at? then
          socket.sendPrivateMessage(sender, "Request ##{request.id} could not be deleted as it has already been filled")
        elsif request.submitter == sender then
          request.destroy
          socket.sendPrivateMessage(sender, "Request ##{request.id} has been deleted")
          if request.claimer? then
            socket.sendPrivateMessage(request.claimer, "Request ##{request.id} has been deleted by #{sender}")
          end
          socket.sendPublicMessage("Request ##{request.id} \"#{request.request}\" has been deleted by #{sender}")
        else
          socket.sendPrivateMessage(sender, "You do not have permission to delete request ##{request.id}")
        end
      rescue ActiveRecord::RecordNotFound
        socket.sendPrivateMessage(sender, "That request could not be found")
      end
    else
      socket.sendPrivateMessage(sender, "That command must be executed in private chat only")
    end
  end
  
  def self.cmd_delete_help
    ["RequestNum", "Deletes a request you submitted. ex. #{CMD_PREFIX}delete 12"]
  end
  
  def self.cmd_search(hub, sender, isprivate, args)
    if args.blank? then
      HelpPlugin.send_usage(hub, sender, "search")
    else
      requests = Request.find(:all, :conditions => ["filled_at IS NULL and request LIKE ?", "%#{args}%"])
      if requests.blank? then
        hub.sendPrivateMessage(sender, "No requests matched your query")
      else
        hub.sendPrivateMessage(sender, "Matched requests:")
        send_request_list hub, sender, requests
      end
    end
  end
  
  def self.cmd_search_help
    ["SearchString", "Searches all requests for those matching SearchString"]
  end
end
