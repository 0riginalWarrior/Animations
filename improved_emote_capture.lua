--// IMPROVED EMOTE CAPTURE SCRIPT
local player = game:GetService("Players").LocalPlayer
game.Players.LocalPlayer.Character.Animate.Disabled = true

-- Excluded animation IDs (optional)
local excludedIds = {
    ["10921302207"] = true,
    ["10921307241"] = true,
    ["10921308158"] = true,
    ["10921306285"] = true,
    ["10921312010"] = true,
    ["10921301576"] = true
}

-- Create save folders if missing
if not isfolder("emotes") then makefolder("emotes") end
if not isfolder("Audios") then makefolder("Audios") end

-- Session management
local currentSession = nil
local sessions = {}

-- Helpers
local function serializeCFrame(cf)
    local c = { cf:GetComponents() }
    return string.format("CFrame.new(%s)", table.concat(c, ", "))
end

-- Start new capture session
local function startSession(emoteName)
    -- If there's already an active session, save it first
    if currentSession then
        saveSession(currentSession)
    end
    
    currentSession = emoteName
    sessions[emoteName] = {
        animations = {},
        audios = {},
        animIdSet = {}, -- for deduplication
        audioSet = {}   -- for deduplication
    }
    
    print("🟢 Started capture session for:", emoteName)
    
    -- Immediately capture what's currently playing
    captureCurrentlyPlaying()
    
    -- Set up audio monitoring
    setupAudioMonitoring()
end

-- Capture currently playing animations and audios
local function captureCurrentlyPlaying()
    if not currentSession then return end
    
    local sessionData = sessions[currentSession]
    local char = player.Character
    
    -- Capture playing animations
    if char then
        local hum = char:FindFirstChildWhichIsA("Humanoid")
        if hum then
            for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                local anim = track.Animation
                if anim and anim.AnimationId then
                    local animId = anim.AnimationId:match("%d+")
                    if animId and not excludedIds[animId] and not sessionData.animIdSet[animId] then
                        sessionData.animIdSet[animId] = true
                        table.insert(sessionData.animations, animId)
                        print("🎥 Captured current animation ID (session:", currentSession .. "):", animId)
                    end
                end
            end
        end
    end
    
    -- Capture existing audios
    local audioFolder = player.PlayerGui:FindFirstChild("emote_audio")
    if audioFolder then
        for _, child in ipairs(audioFolder:GetChildren()) do
            if child:IsA("Sound") and not sessionData.audioSet[child] then
                sessionData.audioSet[child] = true
                table.insert(sessionData.audios, child)
                print("🎵 Captured current audio (session:", currentSession .. "):", child.SoundId)
            end
        end
    end
end

-- Audio monitoring connections
local audioChildConn = nil
local playerGuiChildConn = nil

-- Setup audio monitoring for current session
local function setupAudioMonitoring()
    -- Clean up old connections
    if audioChildConn then
        pcall(function() audioChildConn:Disconnect() end)
        audioChildConn = nil
    end
    if playerGuiChildConn then
        pcall(function() playerGuiChildConn:Disconnect() end)
        playerGuiChildConn = nil
    end
    
    local audioFolder = player.PlayerGui:FindFirstChild("emote_audio")
    if audioFolder then
        -- Monitor for new sounds added to existing folder
        audioChildConn = audioFolder.ChildAdded:Connect(function(child)
            if currentSession and child:IsA("Sound") then
                local sessionData = sessions[currentSession]
                if not sessionData.audioSet[child] then
                    sessionData.audioSet[child] = true
                    table.insert(sessionData.audios, child)
                    print("🎵 Detected new audio (session:", currentSession .. "):", child.SoundId)
                end
            end
        end)
    else
        -- Monitor for emote_audio folder creation
        playerGuiChildConn = player.PlayerGui.ChildAdded:Connect(function(child)
            if child and child.Name == "emote_audio" then
                -- Set up monitoring for this new folder
                if audioChildConn then pcall(function() audioChildConn:Disconnect() end) end
                audioChildConn = child.ChildAdded:Connect(function(sound)
                    if currentSession and sound:IsA("Sound") then
                        local sessionData = sessions[currentSession]
                        if not sessionData.audioSet[sound] then
                            sessionData.audioSet[sound] = true
                            table.insert(sessionData.audios, sound)
                            print("🎵 Detected new audio (session:", currentSession .. "):", sound.SoundId)
                        end
                    end
                end)
                
                -- Capture any existing sounds in the new folder
                for _, sound in ipairs(child:GetChildren()) do
                    if currentSession and sound:IsA("Sound") then
                        local sessionData = sessions[currentSession]
                        if not sessionData.audioSet[sound] then
                            sessionData.audioSet[sound] = true
                            table.insert(sessionData.audios, sound)
                            print("🎵 Detected existing audio (session:", currentSession .. "):", sound.SoundId)
                        end
                    end
                end
                
                -- Disconnect the PlayerGui listener since we found the folder
                if playerGuiChildConn then
                    pcall(function() playerGuiChildConn:Disconnect() end)
                    playerGuiChildConn = nil
                end
            end
        end)
    end
end

-- Animation tracking
local function onAnimationPlayed(track)
    if not currentSession then return end
    
    local anim = track.Animation
    if anim and anim.AnimationId then
        local animId = anim.AnimationId:match("%d+")
        if animId and not excludedIds[animId] then
            local sessionData = sessions[currentSession]
            if not sessionData.animIdSet[animId] then
                sessionData.animIdSet[animId] = true
                table.insert(sessionData.animations, animId)
                print("🎥 Detected new animation ID (session:", currentSession .. "):", animId)
            end
        end
    end
end

-- Save merged animations for a session
local function saveSessionAnimations(emoteName, animIds)
    if #animIds == 0 then
        print("⚠ No animations to save for:", emoteName)
        return
    end

    local lines = {}
    table.insert(lines, "return {")
    
    -- Process each animation and merge all keyframes
    local allKeyframes = {}
    
    for i, animId in ipairs(animIds) do
        local success, animAsset = pcall(function()
            return game:GetObjects("rbxassetid://" .. animId)[1]
        end)
        
        if success and animAsset then
            local ok, keyframes = pcall(function() return animAsset:GetKeyframes() end)
            if ok and keyframes then
                -- Add all keyframes to our collection
                for _, keyframe in ipairs(keyframes) do
                    table.insert(allKeyframes, {
                        Time = keyframe.Time,
                        Keyframe = keyframe,
                        AnimIndex = i
                    })
                end
            else
                warn("Failed to get keyframes for animation:", animId)
            end
        else
            warn("Failed to load animation asset:", animId)
        end
    end
    
    -- Sort all keyframes by time
    table.sort(allKeyframes, function(a, b) return a.Time < b.Time end)
    
    -- Create entries for each animation
    for i, animId in ipairs(animIds) do
        local label = emoteName
        if i > 1 then
            label = emoteName .. " " .. tostring(i)
        end
        
        table.insert(lines, string.format("    [\"%s\"] = {", label))
        
        -- Add keyframes for this specific animation
        for _, kfData in ipairs(allKeyframes) do
            if kfData.AnimIndex == i then
                table.insert(lines, string.format("        {Time = %.3f, Data = {", kfData.Time))
                for _, pose in ipairs(kfData.Keyframe:GetDescendants()) do
                    if pose:IsA and pose:IsA("Pose") then
                        table.insert(lines, string.format("            [\"%s\"] = %s,", pose.Name, serializeCFrame(pose.CFrame)))
                    end
                end
                table.insert(lines, "        }},")
            end
        end
        
        table.insert(lines, "    },")
    end
    
    table.insert(lines, "}")
    local output = table.concat(lines, "\n")
    writefile("emotes/" .. emoteName .. ".lua", output)
    print("✅ Saved merged keyframes to emotes/" .. emoteName .. ".lua")
end

-- Save audios for a session
local function saveSessionAudios(emoteName, audios)
    if #audios == 0 then
        print("⚠ No audios to save for:", emoteName)
        return
    end

    for i, sound in ipairs(audios) do
        if sound and sound:IsA and sound:IsA("Sound") then
            local filename = emoteName
            if i > 1 then
                filename = string.format("%s (%d)", emoteName, i)
            end
            
            local lines = {
                "SoundId: " .. tostring(sound.SoundId),
                "PlaybackSpeed: " .. tostring(sound.PlaybackSpeed),
                "TimeLength: " .. tostring(sound.TimeLength)
            }
            
            writefile("Audios/" .. filename .. ".txt", table.concat(lines, "\n"))
            print("✅ Saved audio info to Audios/" .. filename .. ".txt")
        end
    end
end

-- Save complete session
function saveSession(emoteName)
    local sessionData = sessions[emoteName]
    if not sessionData then
        print("⚠ No session data found for:", emoteName)
        return
    end

    print("💾 Saving session for:", emoteName)
    print("   - Animations:", #sessionData.animations)
    print("   - Audios:", #sessionData.audios)
    
    saveSessionAnimations(emoteName, sessionData.animations)
    saveSessionAudios(emoteName, sessionData.audios)
    
    -- Clean up session data
    sessions[emoteName] = nil
    
    print("✅ Session saved and cleaned up for:", emoteName)
end

-- Track animations for current character
local function trackAnims()
    local function attachToCharacter(char)
        local hum = char:WaitForChild("Humanoid")
        hum.AnimationPlayed:Connect(onAnimationPlayed)
    end

    if player.Character then
        attachToCharacter(player.Character)
    end
    
    player.CharacterAdded:Connect(function(char)
        attachToCharacter(char)
    end)
end

-- Hook up emote buttons
local function hookButtons()
    local emoteFolder = player.PlayerGui:WaitForChild("EmoteUI"):WaitForChild("Core"):WaitForChild("Emotes")
    
    for _, btn in ipairs(emoteFolder:GetDescendants()) do
        if btn:IsA("TextButton") and btn:FindFirstChild("EmoteTitle") then
            btn.MouseButton1Click:Connect(function()
                local emoteName = btn.EmoteTitle.Text or "Emote"
                startSession(emoteName)
                
                -- Small delay to catch initial audios
                task.wait(0.1)
                captureCurrentlyPlaying()
            end)
        end
    end
end

-- Initialize
trackAnims()
hookButtons()

print("🚀 Improved Emote Capture Script loaded!")
print("📝 Click any emote button to start capturing")
print("🔄 Multiple animations/audios will be merged into the same session")
print("💾 Click a different emote button to save current session and start new one")