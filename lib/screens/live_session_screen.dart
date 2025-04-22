import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:jitsi_meet_wrapper/jitsi_meet_wrapper.dart';
import '../providers/auth_provider.dart';
import '../models/session.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({Key? key}) : super(key: key);

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  bool _isLoading = true;
  bool _isJoining = false;
  bool _hasJoined = false;
  String? _error;
  LiveSession? _session;
  bool _isMuted = false;
  bool _isVideoOff = false;
  String? _displayName; // Added to track the display name

  @override
  void initState() {
    super.initState();
    // Initialize session when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSession();
      _loadSavedDisplayName(); // Load any previously saved display name
    });
  }

  // Load saved display name from SharedPreferences
  Future<void> _loadSavedDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('jitsi_display_name');
      if (savedName != null && savedName.isNotEmpty) {
        setState(() {
          _displayName = savedName;
        });
        debugPrint("Loaded saved display name: $_displayName");
      }
    } catch (e) {
      debugPrint("Error loading saved display name: $e");
    }
  }

  Future<void> _initializeSession() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      final sessionId = args['sessionId'] as String;
      
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;
      
      if (token == null) {
        throw Exception('Not authenticated');
      }
      
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null) {
        throw Exception('API_URL not found in environment variables');
      }
      
      final url = Uri.parse('$apiUrl/sessions/$sessionId');
      debugPrint('Fetching session details from: $url');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('Fetch session details response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final sessionData = json.decode(response.body);
        if (mounted) {
          setState(() {
            _session = LiveSession.fromJson(sessionData);
            _isLoading = false;
          });
        }
      } else if (response.statusCode == 403) {
        if (mounted) {
          setState(() {
            _error = 'You must be enrolled in the course to access this session';
            _isLoading = false;
          });
        }
      } else {
        final responseData = json.decode(response.body);
        if (mounted) {
          setState(() {
            _error = responseData['detail'] ?? 'Failed to fetch session details';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Initialize session error: $e');
      if (mounted) {
        setState(() {
          _error = 'An error occurred: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestPermissions() async {
    debugPrint("Requesting permissions...");
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    
    debugPrint("Camera permission: ${statuses[Permission.camera]}");
    debugPrint("Microphone permission: ${statuses[Permission.microphone]}");
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
  }

  // Verify and potentially update the user's display name
  Future<bool> _verifyAndUpdateDisplayName() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    
    // Start with the user's name from auth provider
    String? nameToUse = user?.name;
    
    // If name is missing or empty, show a dialog to get it
    if (nameToUse == null || nameToUse.trim().isEmpty) {
      // Check if we have a saved display name
      if (_displayName != null && _displayName!.isNotEmpty) {
        nameToUse = _displayName;
      } else {
        // Show dialog to get name
        nameToUse = await _showNameInputDialog();
        
        // If user cancelled or entered empty name, return false
        if (nameToUse == null || nameToUse.trim().isEmpty) {
          setState(() {
            _error = 'A valid display name is required to join the meeting';
          });
          return false;
        }
      }
    }
    
    // Store the verified name - FIX: Added null check with ! operator
    _displayName = nameToUse!.trim();
    await _storeUserName(_displayName!);
    
    debugPrint("Verified display name: $_displayName");
    return true;
  }

  // Show a dialog to get the user's name
  Future<String?> _showNameInputDialog() async {
    String? enteredName;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Your Name'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Your name will be visible to others',
            ),
            onChanged: (value) {
              enteredName = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                enteredName = null;
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    
    return enteredName;
  }

  // Store user name in local storage to ensure it persists
  Future<void> _storeUserName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jitsi_display_name', name);
      debugPrint("Stored user display name in preferences: $name");
    } catch (e) {
      debugPrint("Error storing user name: $e");
    }
  }

  Future<void> _joinMeeting() async {
    // Verify and update display name
    if (!await _verifyAndUpdateDisplayName()) {
      return;
    }
    
    // Request permissions first
    await _requestPermissions();
    
    // Check if permissions are granted
    bool cameraGranted = await Permission.camera.isGranted;
    bool microphoneGranted = await Permission.microphone.isGranted;
    
    debugPrint("Camera granted: $cameraGranted, Microphone granted: $microphoneGranted");
    
    if (!cameraGranted || !microphoneGranted) {
      setState(() {
        _error = 'Camera and microphone permissions are required to join the meeting';
      });
      return;
    }
    
    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      // Use the meeting link from the session if available, otherwise generate one
      final roomName = _session?.meetingLink?.split('/').last ?? 
                     'learnlive-session-${_session?.id ?? DateTime.now().millisecondsSinceEpoch}';
      
      debugPrint("Joining room: $roomName with display name: $_displayName");
      
      // Get user email - FIX: Added mounted check before accessing context in async method
      String? userEmail;
      if (mounted) {
        userEmail = Provider.of<AuthProvider>(context, listen: false).user?.email;
      }
      
      // Configuration specifically to enforce display name
      final options = JitsiMeetingOptions(
        roomNameOrUrl: roomName, // Use direct room name instead of custom URL
        serverUrl: "https://meet.jit.si",
        subject: _session?.title ?? 'Live Session',
        userDisplayName: _displayName, // Use verified display name
        userEmail: userEmail,
        isAudioMuted: _isMuted,
        isVideoMuted: _isVideoOff,
        configOverrides: {
          // Core settings
          "startWithAudioMuted": _isMuted,
          "startWithVideoMuted": _isVideoOff,
          "disableDeepLinking": true,
          
          // Name enforcement settings - ENHANCED
          "displayName": _displayName,
          "defaultDisplayName": _displayName,
          "userInfo": {
            "displayName": _displayName
          },
          "defaultLocalDisplayName": _displayName,
          "defaultRemoteDisplayName": "Participant",
          "readOnlyName": true,
          "disableProfile": true,
          "disableEditDisplayName": true,
          "prejoinConfig": {
            "enabled": false,
            "hideDisplayName": false,
            "hideExtraJoinButtons": true
          },
          
          // Disable all pre-join screens
          "requireDisplayName": true,
          "enableWelcomePage": false,
          "enableClosePage": false,
          "prejoinPageEnabled": false,
          
          // Critical settings to bypass lobby
          "lobby.enabled": false,
          "enableLobby": false,
          "hideLobbyButton": true,
          "disableLobbyPassword": true,
          "enableInsecureRoomNameWarning": false,
          
          // Disable password requirements
          "roomPasswordRequired": false,
          "lockRoomGuestEnabled": false,
          "securityUi.enabled": false,
          
          // Disable moderator features
          "enableUserRolesBasedOnToken": false,
          "disableModeratorIndicator": true,
          "disableFocusIndicator": true,
          
          // Set as participant by default (not moderator)
          "defaultRole": "participant",
          
          // Disable waiting for host
          "waitForHost": false,
          "startSilent": false,
          
          // Auto-join settings
          "autoJoin": true,
          "doNotStoreRoom": true,
          "enableAutoJoin": true,
          
          // Disable chat features that might require permissions
          "enableLobbyChat": false,
          "lobby.enableForceMute": false,
          
          // Toolbar configuration
          "toolbarButtons": [
            'microphone', 'camera', 'closedcaptions', 'desktop', 'fullscreen',
            'fodeviceselection', 'hangup', 'chat', 'recording',
            'livestreaming', 'etherpad', 'sharedvideo', 'settings', 'raisehand',
            'videoquality', 'filmstrip', 'feedback', 'stats', 'shortcuts',
            'tileview', 'videobackgroundblur', 'download', 'help'
            // Removed 'profile' to prevent name changes
          ],
        },
        featureFlags: {
          // Core features
          "welcomepage.enabled": false,
          "pip.enabled": true,
          "chat.enabled": true,
          
          // Disable security features
          "invite.enabled": false,
          "meeting-password.enabled": false,
          "security-options.enabled": false,
          "lobby-mode.enabled": false,
          
          // Disable pre-join screens
          "prejoinpage.enabled": false,
          
          // Disable moderator features
          "moderator.enabled": false,
          "kick-out.enabled": false,
          "overflow-menu.enabled": false,
          
          // Disable recording/streaming
          "recording.enabled": false,
          "live-streaming.enabled": false,
          
          // Enable basic UI features
          "tile-view.enabled": true,
          "raise-hand.enabled": true,
          "filmstrip.enabled": true,
          "notifications.enabled": true,
          
          // Additional flags to bypass security
          "add-people.enabled": false,
          "calendar.enabled": false,
          "call-integration.enabled": false,
          "close-captions.enabled": false,
          "help.enabled": false,
          "ios.recording.enabled": false,
          "transcription.enabled": false,
          
          // Force auto-join
          "prejoinpage.hideExtraJoinButtons": true,
          
          // Name enforcement flags - ENHANCED
          "display-name.enabled": true,
          "display-name.editable": false,
          "profile.enabled": false,
          
          // Set resolution
          "resolution": 720,
        },
        // Set token to empty to avoid authentication
        token: "",
      );

      debugPrint("Joining with options: $options");
      
      // Join the meeting
      await JitsiMeetWrapper.joinMeeting(
        options: options,
        listener: JitsiMeetingListener(
          onConferenceWillJoin: (url) {
            debugPrint("onConferenceWillJoin: url: $url");
            if (mounted) {
              setState(() {
                _isJoining = true;
              });
            }
          },
          onConferenceJoined: (url) {
            debugPrint("onConferenceJoined: url: $url");
            if (mounted) {
              setState(() {
                _isJoining = false;
                _hasJoined = true;
              });
            }
            
            // Log success message for display name
            debugPrint("Successfully joined with display name: $_displayName");
          },
          onConferenceTerminated: (url, error) {
            debugPrint("onConferenceTerminated: url: $url, error: $error");
            if (mounted) {
              setState(() {
                _hasJoined = false;
              });
            }
          },
          onParticipantJoined: (email, name, role, participantId) {
            // Log when a participant joins to verify names are showing correctly
            debugPrint("Participant joined - Name: $name, Email: $email, Role: $role, ID: $participantId");
            
            // Check if this is the local user (usually the first to join)
            if (mounted && email == Provider.of<AuthProvider>(context, listen: false).user?.email) {
              debugPrint("Local user joined with name: $name (should be: $_displayName)");
              
              // If name doesn't match what we set, log an error
              if (name != _displayName) {
                debugPrint("WARNING: Display name mismatch! Expected: $_displayName, Got: $name");
              }
            }
          },
        ),
      );
    } catch (e) {
      debugPrint("Error joining meeting: $e");
      if (mounted) {
        setState(() {
          _isJoining = false;
          _error = "Error joining meeting: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live Session'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live Session'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_session?.title ?? 'Live Session'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Session info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _session?.title ?? '',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _session?.description ?? '',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(Icons.info_outline, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Make sure your camera and microphone are working properly before joining.',
                              style: TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Direct access enabled - no permission or password required.',
                              style: TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      // Display name indicator
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You will join as: ${_displayName ?? Provider.of<AuthProvider>(context).user?.name ?? "Set your name"}',
                              style: const TextStyle(fontSize: 14, color: Colors.blue, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (_displayName != null)
                            IconButton(
                              icon: const Icon(Icons.edit, size: 14),
                              onPressed: () async {
                                final newName = await _showNameInputDialog();
                                if (newName != null && newName.isNotEmpty) {
                                  setState(() {
                                    _displayName = newName;
                                  });
                                  await _storeUserName(newName);
                                }
                              },
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Join meeting button
              if (_isJoining)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Joining the session directly...'),
                    ],
                  ),
                )
              else if (_hasJoined)
                Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Session joined successfully',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You can return to the session at any time.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _joinMeeting,
                      child: const Text('Rejoin Session'),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    // Video preview placeholder
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.videocam,
                          size: 64,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Audio/Video settings
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Microphone toggle
                        Column(
                          children: [
                            IconButton(
                              onPressed: _toggleMute,
                              icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                              style: IconButton.styleFrom(
                                backgroundColor: _isMuted ? Colors.red.shade100 : Colors.grey[200],
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(_isMuted ? 'Unmute' : 'Mute', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(width: 24),
                        // Video toggle
                        Column(
                          children: [
                            IconButton(
                              onPressed: _toggleVideo,
                              icon: Icon(_isVideoOff ? Icons.videocam_off : Icons.videocam),
                              style: IconButton.styleFrom(
                                backgroundColor: _isVideoOff ? Colors.red.shade100 : Colors.grey[200],
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(_isVideoOff ? 'Turn On' : 'Turn Off', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _joinMeeting,
                        icon: const Icon(Icons.video_call),
                        label: const Text('Join Directly (No Password/Permission)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8852E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              
              const SizedBox(height: 24),
              
              // Session details
              const Text(
                'Session Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Teacher'),
                subtitle: Text(_session?.teacher ?? ''),
              ),
              ListTile(
                leading: const Icon(Icons.book),
                title: const Text('Course'),
                subtitle: Text(_session?.course ?? ''),
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Duration'),
                subtitle: Text('${_session?.duration ?? 0} minutes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}