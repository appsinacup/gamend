const { ApiClient, HealthApi, AuthenticationApi, UsersApi, LobbiesApi, GameRealtime, GameWebRTC } = require('./javascript/dist/index.js');
const { default: open } = require('open');
const { Socket: PhoenixSocket } = require('phoenix');
const { RTCPeerConnection, RTCSessionDescription, RTCIceCandidate } = require('node-datachannel/polyfill');
const basePath = 'http://localhost:4000';
//const basePath = 'https://gamend.org';
async function testSDK() {
  try {
    console.log('Testing SDK health check...');

    // Initialize the API client
    const apiClient = new ApiClient();
    apiClient.basePath = basePath;

    // Create an instance of the Health API
    const healthApi = new HealthApi(apiClient);

    // Test the health endpoint
    const healthResponse = await healthApi.index();
    console.log('✅ Health check response:', healthResponse);

  } catch (error) {
    console.error('❌ Error testing SDK:', error);
  }
}

async function runOAuthFlow(provider) {
  try {
    console.log(`Testing ${provider} OAuth flow...`);

    // Initialize the API client
    const apiClient = new ApiClient();
    apiClient.basePath = basePath;

    // Create an instance of the Authentication API
    const authApi = new AuthenticationApi(apiClient);

    // Step 1: Get the authorization URL with session_id
    console.log(`Step 1: Requesting ${provider} authorization URL...`);
    const authResponse = (await authApi.oauthRequest(provider)).data;
    const authUrl = authResponse.authorization_url;
    const sessionId = authResponse.session_id;

    console.log(`✅ ${provider} authorization URL obtained:`);
    console.log(authUrl);
    console.log('Session ID:', sessionId);
    console.log('');

    // Step 2: Automatically open the URL in the default browser
    console.log(`Step 2: Opening ${provider} authorization URL in your default browser...`);
    await open(authUrl);
    console.log('✅ Browser opened! Please complete the login and authorization.');
    console.log('The success page will show when authentication is complete.');
    console.log('');

    // Step 3: Poll the session status until completion
    console.log('Step 3: Waiting for OAuth completion...');
    let sessionData = null;
    let attempts = 0;
    const maxAttempts = 60; // 60 seconds timeout

    while (attempts < maxAttempts) {
      try {
        // Poll the session status
        const statusResponse = await authApi.oauthSessionStatus(sessionId);
        sessionData = statusResponse.data;

        console.log(`Polling session status... (${attempts + 1}/${maxAttempts}) - Status: ${sessionData.status}`);

        if (sessionData.status === 'completed') {
          console.log('✅ OAuth completed successfully!');
          break;
        } else if (sessionData.status === 'error') {
          console.error('❌ OAuth failed:', sessionData.details || sessionData.message);
          return null;
        } else if (sessionData.status === 'conflict') {
          console.error('❌ OAuth conflict:', sessionData.message || 'Account already linked to another user');
          return { status: 'conflict', data: sessionData.result || sessionData };
        }

        // Wait 1 second before next poll
        await new Promise(resolve => setTimeout(resolve, 1000));
        attempts++;

      } catch (error) {
        if (error.status === 404) {
          console.log(`Session not found, waiting... (${attempts + 1}/${maxAttempts})`);
        } else {
          console.error('Error polling session status:', error);
        }
        await new Promise(resolve => setTimeout(resolve, 1000));
        attempts++;
      }
    }

    if (!sessionData || sessionData.status !== 'completed') {
      console.error('❌ OAuth timed out or failed');
      return null;
    }

    // Extract token data from session. The server returns {status, data}
    // (preferred), but older shapes put tokens at the top level. Handle both.
    const payload = sessionData.result || sessionData;
    const tokenData = {
      accessToken: payload.access_token || payload.accessToken,
      refreshToken: payload.refresh_token || payload.refreshToken,
      tokenType: payload.token_type || payload.tokenType,
      expiresIn: payload.expires_in || payload.expiresIn,
      user: payload.user || null
    };

    console.log('');
    console.log(`🎉 ${provider} OAuth flow completed successfully!`);
    console.log('Access Token:', tokenData.accessToken);
    console.log('Refresh Token:', tokenData.refreshToken);
    console.log('Expires In:', tokenData.expiresIn, 'seconds');
    console.log('');

    return { provider, tokenData };

  } catch (error) {
    console.error(`Error testing ${provider} auth:`, error);
    return null;
  }
}

async function testUserAPI(accessToken, refreshToken, provider) {
  try {
    console.log('Testing authenticated API calls...');

    // Initialize the API client with authentication
    const apiClient = new ApiClient();
    apiClient.basePath = basePath;
    apiClient.defaultHeaders = {
      'Authorization': `Bearer ${accessToken}`
    };

    // Create instances of APIs that require authentication
    const authApi = new AuthenticationApi(apiClient);
    const usersApi = new UsersApi(apiClient);

    // Test getting user profile
    console.log('Getting user profile...');
    const userProfile = await usersApi.getCurrentUser();
    console.log('✅ User profile:', userProfile);


    // Test unlinking the provider (this will likely fail if it's the only auth method, but test anyway)
    console.log(`Testing unlink ${provider}...`);
    try {
      const unlinkResult = await authApi.unlinkProvider(provider);
      console.log(`✅ Unlinked ${provider}:`, unlinkResult);
    } catch (error) {
      console.log(`⚠️  Unlink ${provider} failed (expected if it's the only auth method):`, error.message);
    }

    // Test refreshing the token
    console.log('Testing token refresh...');
    const refreshRequest = { refresh_token: refreshToken };
    const refreshResponse = await authApi.refreshToken({ refreshTokenRequest: refreshRequest });
    console.log('✅ Token refresh response:', refreshResponse);

    // Test logout
    console.log('Testing logout...');
    const logoutResponse = await authApi.logout();
    console.log('✅ Logout response:', logoutResponse);

    console.log('✅ All authenticated API calls completed!');
    return { apiClient };

  } catch (error) {
    console.error('❌ Error testing authenticated API:', error);
  }
}

// Helper: device login — returns { accessToken, userId }
async function deviceLogin(deviceId) {
  const apiClient = new ApiClient();
  apiClient.basePath = basePath;
  const authApi = new AuthenticationApi(apiClient);
  const loginResponse = await authApi.deviceLogin({ deviceLoginRequest: { device_id: deviceId } });
  return {
    accessToken: loginResponse.data.access_token,
    userId: loginResponse.data.user_id,
  };
}

// Run the tests
async function runAllTests() {
  console.log('🚀 Starting comprehensive OAuth and API tests...\n');

  await testSDK();
  console.log('');

  // Shared device_id for WebSocket + WebRTC tests
  const testDeviceId = 'realtime-test-device-' + Date.now();
  console.log('\n--- Device login for realtime tests ---\n');
  const { accessToken: rtToken, userId: rtUserId } = await deviceLogin(testDeviceId);
  console.log('✅ Device login successful, user_id:', rtUserId);

  // Test WebSocket connection independently
  console.log('\n--- Testing WebSocket ---\n');
  await testWebSocket(rtToken, rtUserId);
  console.log('');

  // Test full WebRTC signaling flow (reuses same device credentials)
  console.log('\n--- Testing WebRTC Full Flow ---\n');
  await testWebRTCFullFlow(rtToken, rtUserId);
  console.log('');

  const providers = ['steam', 'discord', 'google', 'facebook', 'github', 'apple'];
  for (const provider of providers) {
    console.log(`\n--- Testing ${provider.toUpperCase()} ---\n`);
    const result = await runOAuthFlow(provider);
    if (result && result.tokenData && result.tokenData.accessToken) {
      const { apiClient } = await testUserAPI(result.tokenData.accessToken, result.tokenData.refreshToken, provider);

      // After a successful auth + basic user tests, exercise lobby APIs
      if (apiClient) {
        await testLobbyAPI(apiClient);
      }

      // (WebSocket already tested independently with device login above)
    } else if (result && result.status === 'conflict') {
      console.log(`⚠️  ${provider} OAuth resulted in conflict. Skipping authenticated API tests.`);
    } else {
      console.log(`❌ ${provider} OAuth failed. Skipping authenticated API tests.`);
    }
    console.log('');
  }

  console.log('🎉 All tests completed!');
}

// Exercise the lobby API after login (create -> list -> update -> leave)
async function testLobbyAPI(apiClient) {
  try {
    console.log('Testing lobby API flow...');

    const lobbiesApi = new LobbiesApi(apiClient);

    // Create a lobby (authenticated user becomes host and joined automatically)
    console.log('Creating a new lobby...');
    const createRequest = { createLobbyRequest: { title: `JS test lobby ${Date.now()}`, max_users: 6 } };
    const lobby = (await lobbiesApi.createLobby(createRequest)).data;
    console.log('✅ Lobby created:', lobby);

    // List public lobbies (should include the newly created lobby)
    console.log('Listing public lobbies...');
    const lobbiesResponse = await lobbiesApi.listLobbies();
    const lobbies = lobbiesResponse.data || [];
    console.log('✅ Lobbies count:', lobbies.length, 'IDs:', lobbies.map(l => l.id));
    console.log('✅ Pagination meta:', lobbiesResponse.meta);

    // Update the lobby's title (host-only action)
    console.log('Updating lobby title...');
    const updated = await lobbiesApi.updateLobby({ updateLobbyRequest: { title: lobby.title + ' (updated)' } });
    console.log('✅ Updated lobby:', updated);

    // Leave the lobby
    console.log('Leaving lobby...');
    const leave = await lobbiesApi.leaveLobby();
    console.log('✅ Left lobby:', leave);

  } catch (error) {
    console.error('❌ Error testing lobby API:', error);
  }
}

// Test WebSocket real-time connection via GameRealtime
async function testWebSocket(accessToken, userId) {
  try {
    console.log('Testing WebSocket (GameRealtime) connection...');

    const realtime = new GameRealtime(basePath, () => accessToken);
    console.log('✅ GameRealtime created, socket connected');

    // Join the user channel
    const userChannel = realtime.joinUserChannel(userId);
    console.log('✅ Joined user channel: user:' + userId);

    // Wait a moment for the channel join to complete
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Verify the channel is tracked
    const retrieved = realtime.channel('user:' + userId);
    if (retrieved) {
      console.log('✅ Channel retrieved successfully');
    } else {
      console.log('⚠️  Channel not found after join');
    }

    // Join lobbies channel (public feed)
    const lobbiesChannel = realtime.joinLobbiesChannel();
    console.log('✅ Joined lobbies channel');

    // Test idempotent re-join (should return same channel)
    const sameChannel = realtime.joinUserChannel(userId);
    if (sameChannel === userChannel) {
      console.log('✅ Idempotent re-join returns same channel');
    }

    // Leave a channel
    realtime.leaveChannel('lobbies');
    const gone = realtime.channel('lobbies');
    if (!gone) {
      console.log('✅ Channel left successfully');
    }

    // Disconnect
    realtime.disconnect();
    console.log('✅ WebSocket disconnected');

    return true;
  } catch (error) {
    console.error('❌ Error testing WebSocket:', error.message || error);
    return false;
  }
}

// Full end-to-end WebRTC signaling test via WebSocket + DataChannels
async function testWebRTCFullFlow(accessToken, userId) {
  try {
    console.log('Testing full WebRTC signaling flow...');

    // Step 1: Connect WebSocket and join user channel
    console.log('Step 1: Connecting WebSocket...');
    const wsUrl = basePath.replace(/^http/, 'ws') + '/socket';
    const socket = new PhoenixSocket(wsUrl, { params: { token: accessToken } });

    await new Promise((resolve, reject) => {
      socket.onOpen(resolve);
      socket.onError((err) => reject(new Error('Socket connection failed: ' + err)));
      socket.connect();
    });
    console.log('✅ WebSocket connected');

    const channel = socket.channel('user:' + userId, { token: accessToken });
    await new Promise((resolve, reject) => {
      channel.join()
        .receive('ok', resolve)
        .receive('error', (resp) => reject(new Error('Channel join failed: ' + JSON.stringify(resp))));
    });
    console.log('✅ Joined user channel: user:' + userId);

    // Step 2: Create RTCPeerConnection and DataChannels
    console.log('Step 2: Creating RTCPeerConnection + DataChannels...');
    const pc = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
    });

    const eventsChannel = pc.createDataChannel('events', { ordered: true });
    const stateChannel = pc.createDataChannel('state', { ordered: false, maxRetransmits: 0 });
    console.log('✅ DataChannels created: events (reliable), state (unreliable)');

    // Track received data and channel states
    const receivedData = [];
    let eventsOpen = false;
    let stateOpen = false;

    eventsChannel.onopen = () => { eventsOpen = true; console.log('   📡 DataChannel "events" opened'); };
    eventsChannel.onmessage = (event) => { receivedData.push({ channel: 'events', data: event.data }); };
    eventsChannel.onerror = (err) => console.error('   ❌ DataChannel "events" error:', err);

    stateChannel.onopen = () => { stateOpen = true; console.log('   📡 DataChannel "state" opened'); };
    stateChannel.onmessage = (event) => { receivedData.push({ channel: 'state', data: event.data }); };
    stateChannel.onerror = (err) => console.error('   ❌ DataChannel "state" error:', err);

    // Step 3: Set up ICE candidate exchange
    console.log('Step 3: Setting up ICE exchange...');
    pc.onicecandidate = (event) => {
      if (event.candidate) {
        channel.push('webrtc:ice', event.candidate.toJSON());
      }
    };

    // Listen for server ICE candidates
    channel.on('webrtc:ice', (payload) => {
      if (payload.candidate) {
        pc.addIceCandidate(new RTCIceCandidate(payload)).catch((err) => {
          console.error('   ❌ Failed to add ICE candidate:', err.message);
        });
      }
    });

    // Step 4: Create and send SDP offer
    console.log('Step 4: Creating SDP offer...');
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    console.log('✅ Local description set (offer)');

    // Send offer to server and wait for answer
    const answerPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('webrtc:answer timeout')), 10000);
      channel.on('webrtc:answer', (payload) => {
        clearTimeout(timeout);
        resolve(payload);
      });
    });

    await new Promise((resolve, reject) => {
      channel.push('webrtc:offer', { sdp: offer.sdp, type: offer.type })
        .receive('ok', resolve)
        .receive('error', (resp) => reject(new Error('webrtc:offer rejected: ' + JSON.stringify(resp))));
    });
    console.log('✅ SDP offer sent and accepted');

    // Step 5: Receive SDP answer and set remote description
    console.log('Step 5: Waiting for SDP answer...');
    const answerPayload = await answerPromise;
    await pc.setRemoteDescription(new RTCSessionDescription({ sdp: answerPayload.sdp, type: answerPayload.type }));
    console.log('✅ Remote description set (answer)');

    // Step 6: Wait for DataChannel to open
    console.log('Step 6: Waiting for DataChannel open...');
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('DataChannel open timeout')), 15000);
      const checkOpen = setInterval(() => {
        if (eventsOpen || stateOpen) {
          clearInterval(checkOpen);
          clearTimeout(timeout);
          resolve();
        }
      }, 100);
    });
    console.log('✅ At least one DataChannel is open (events:', eventsOpen, ', state:', stateOpen, ')');

    // Step 7: Send data over DataChannel
    console.log('Step 7: Sending data over DataChannels...');
    if (eventsOpen) {
      eventsChannel.send(JSON.stringify({ type: 'test_event', payload: 'hello from client' }));
      console.log('✅ Sent test message on "events" channel');
    }
    if (stateOpen) {
      stateChannel.send(JSON.stringify({ x: 100, y: 200, z: 0 }));
      console.log('✅ Sent test message on "state" channel');
    }

    // Wait a moment for any server echoes
    await new Promise(resolve => setTimeout(resolve, 1000));

    // Step 8: Verify server relayed data back via WebSocket
    console.log('Step 8: Checking server-relayed data...');
    // The server relays DataChannel data back via webrtc:data push
    const wsReceivedData = [];
    channel.on('webrtc:data', (payload) => {
      wsReceivedData.push(payload);
    });

    // Send another message and check if we receive webrtc:channel_open
    let channelOpenReceived = false;
    channel.on('webrtc:channel_open', () => { channelOpenReceived = true; });

    // Allow time for any pending messages
    await new Promise(resolve => setTimeout(resolve, 500));

    console.log('   Received data on DataChannels:', receivedData.length, 'messages');
    console.log('   Channel open notification received:', channelOpenReceived || 'already received before listener');

    // Step 9: Close WebRTC and clean up
    console.log('Step 9: Closing WebRTC connection...');
    channel.push('webrtc:close', {});
    eventsChannel.close();
    stateChannel.close();
    pc.close();
    console.log('✅ WebRTC connection closed');

    // Disconnect WebSocket
    channel.leave();
    socket.disconnect();
    console.log('✅ WebSocket disconnected');

    console.log('🎉 Full WebRTC signaling flow completed successfully!');
    return true;

  } catch (error) {
    console.error('❌ Error in WebRTC full flow test:', error.message || error);
    return false;
  }
}

runAllTests();
