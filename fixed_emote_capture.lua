--// SETTINGS
local player = game:GetService("Players").LocalPlayer
local HttpService = game:GetService("HttpService")
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

-- Helpers
local function serializeCFrame(cf)
    local c = { cf:GetComponents() }
    return string.format("CFrame.new(%s)", table.concat(c, ", "))
end

-- Session tracking
local currentSession = nil
local sessionAnimations = {}
local sessionAudios = {}
local animIdSet = {} -- for deduplication
local audioSet = {} -- for deduplication

-- Audio monitoring connections
local audioChildConn = nil
local playerGuiChildConn = nil

-- Save merged animations into ONE file with multiple entries
local function saveSessionAnimations(emoteName, animIds)
    if #animIds == 0 then
        print("⚠ No animations to save for:", emoteName)
        return
    end

    local lines = {}
    table.insert(lines, "return {")
    
    -- Collect all keyframes from all animations
    local allKeyframes = {}
    
    for i, animId in ipairs(animIds) do
        print("Loading animation ID:", animId)
        local success, animAsset = pcall(function()
            return game:GetObjects("rbxassetid://" .. animId)[1]
        end)
        
        if success and animAsset then
            local ok, keyframes = pcall(function() return animAsset:GetKeyframes() end)
            if ok and keyframes then
                table.sort(keyframes, function(a,b) return a.Time < b.Time end)
                
                -- Create entry for this animation
                local label = emoteName
                if i > 1 then
                    label = emoteName .. " " .. tostring(i)
                end
                
                table.insert(lines, string.format("    [\"%s\"] = {", label))
                
                for _, keyframe in ipairs(keyframes) do
                    table.insert(lines, string.format("        {Time = %.3f, Data = {", keyframe.Time))
                    for _, pose in ipairs(keyframe:GetDescendants()) do
                        if pose:IsA and pose:IsA("Pose") then
                            table.insert(lines, string.format("            [\"%s\"] = %s,", pose.Name, serializeCFrame(pose.CFrame)))
                        end
                    end
                    table.insert(lines, "        }},")
                end
                
                table.insert(lines, "    },")
            else
                warn("Failed to get keyframes for animation:", animId)
            end
        else
            warn("Failed to load animation:", animId)
        end
    end
    
    table.insert(lines, "}")
    local output = table.concat(lines, "\n")
    writefile("emotes/" .. emoteName .. ".lua", output)
    print("✅ Saved merged animations to emotes/" .. emoteName .. ".lua")
end

-- Save audios as separate files
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

-- Save current session
local function saveCurrentSession()
    if not currentSession then return end
    
    print("💾 Saving session for:", currentSession)
    print("   - Total animations detected:", #sessionAnimations)
    print("   - Total audios detected:", #sessionAudios)
    
    saveSessionAnimations(currentSession, sessionAnimations)
    saveSessionAudios(currentSession, sessionAudios)
    
    print("✅ Session completed for:", currentSession)
end

-- Start new session
local function startNewSession(emoteName)
    -- Save previous session if exists
    if currentSession then
        saveCurrentSession()
    end
    
    -- Reset session data
    currentSession = emoteName
    sessionAnimations = {}
    sessionAudios = {}
    animIdSet = {}
    audioSet = {}
    
    print("🟢 Started new session for:", emoteName)
    
    -- Set up audio monitoring
    setupAudioMonitoring()
    
    -- Capture any currently playing stuff
    captureCurrentlyPlaying()
end

-- Capture currently playing animations and audios
local function captureCurrentlyPlaying()
    if not currentSession then return end
    
    -- Capture playing animations
    local char = player.Character
    if char then
        local hum = char:FindFirstChildWhichIsA("Humanoid")
        if hum then
            for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                local anim = track.Animation
                if anim and anim.AnimationId then
                    local animId = anim.AnimationId:match("%d+")
                    if animId and not excludedIds[animId] and not animIdSet[animId] then
                        animIdSet[animId] = true
                        table.insert(sessionAnimations, animId)
                        print("🎥 Captured current animation ID:", animId)
                    end
                end
            end
        end
    end
    
    -- Capture existing audios
    local audioFolder = player.PlayerGui:FindFirstChild("emote_audio")
    if audioFolder then
        for _, child in ipairs(audioFolder:GetChildren()) do
            if child:IsA("Sound") and not audioSet[child] then
                audioSet[child] = true
                table.insert(sessionAudios, child)
                print("🎵 Captured current audio:", child.SoundId)
            end
        end
    end
end

-- Setup audio monitoring
function setupAudioMonitoring()
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
        -- Monitor existing folder
        audioChildConn = audioFolder.ChildAdded:Connect(function(child)
            if currentSession and child:IsA("Sound") and not audioSet[child] then
                audioSet[child] = true
                table.insert(sessionAudios, child)
                print("🎵 Detected new audio:", child.SoundId)
            end
        end)
    else
        -- Wait for folder to be created
        playerGuiChildConn = player.PlayerGui.ChildAdded:Connect(function(child)
            if child and child.Name == "emote_audio" then
                -- Set up monitoring for new folder
                if audioChildConn then pcall(function() audioChildConn:Disconnect() end) end
                audioChildConn = child.ChildAdded:Connect(function(sound)
                    if currentSession and sound:IsA("Sound") and not audioSet[sound] then
                        audioSet[sound] = true
                        table.insert(sessionAudios, sound)
                        print("🎵 Detected new audio:", sound.SoundId)
                    end
                end)
                
                -- Capture existing sounds
                for _, sound in ipairs(child:GetChildren()) do
                    if currentSession and sound:IsA("Sound") and not audioSet[sound] then
                        audioSet[sound] = true
                        table.insert(sessionAudios, sound)
                        print("🎵 Detected existing audio:", sound.SoundId)
                    end
                end
                
                -- Clean up PlayerGui listener
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
        if animId and not excludedIds[animId] and not animIdSet[animId] then
            animIdSet[animId] = true
            table.insert(sessionAnimations, animId)
            print("🎥 Detected animation ID (session:", currentSession .. "):", animId)
        end
    end
end

-- Hook up character animation tracking
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

-- Hook up buttons under EmoteUI
local function hookButtons()
    local emoteFolder = player.PlayerGui:WaitForChild("EmoteUI"):WaitForChild("Core"):WaitForChild("Emotes")
    
    for _, btn in ipairs(emoteFolder:GetDescendants()) do
        if btn:IsA("TextButton") and btn:FindFirstChild("EmoteTitle") then
            btn.MouseButton1Click:Connect(function()
                local emoteName = btn.EmoteTitle.Text or "Emote"
                startNewSession(emoteName)
            end)
        end
    end
end

-- Initialize
trackAnims()
hookButtons()

print("🚀 Fixed Emote Capture Script loaded!")
print("📝 Click any emote button to start a session")
print("🔄 All animations will be merged into one file until you click a different button")
print("🎵 Each audio will be saved as separate files")
print("⏰ Sessions continue indefinitely until you click a different emote button")