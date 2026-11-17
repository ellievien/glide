package org.localsend.localsend_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pGroup
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.SecureRandom

const val NEARBY_WIFI_CHANNEL = "org.glideapp.glide/nearby_wifi"

private const val TAG = "NearbyWifi"
private const val POLL_INTERVAL_MS = 500L
private const val GROUP_TIMEOUT_MS = 20_000L
private const val JOIN_TIMEOUT_MS = 40_000L

/**
 * The temporary Wi-Fi network of a Nearby transfer (see nearby_service.dart).
 *
 * Hosting creates an autonomous Wi-Fi Direct group. The group owner also acts
 * as a WPA2 access point for "legacy" clients, so iPhones, Macs and PCs can
 * join it like any other network, while other Android devices join it as P2P
 * clients without leaving their current Wi-Fi.
 *
 * Every call runs on the main looper, which is also where the Wi-Fi P2P
 * callbacks arrive, so the state below needs no further synchronization.
 */
class NearbyWifi(context: Context) : MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val p2pManager = this.context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
    private val wifiManager = this.context.getSystemService(Context.WIFI_SERVICE) as WifiManager?
    private var p2pChannel: WifiP2pManager.Channel? = null

    /** The group this device owns, while hosting. */
    private var hosted: Map<String, Any>? = null

    /** Joined another device's group as a P2P client (Android 10+). */
    private var joinedAsP2pClient = false

    /** Network added through the legacy WifiManager API (before Android 10). */
    private var legacyNetworkId: Int? = null

    private val hasWifiDirect: Boolean
        get() = p2pManager != null && context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val once = OnceResult(result)
        try {
            when (call.method) {
                "capabilities" -> once.success(
                    mapOf(
                        "canHost" to hasWifiDirect,
                        // Joining a group by name and passphrase needs Android 10; before
                        // that, the group is joined as a plain access point instead.
                        "canJoin" to (hasWifiDirect || wifiManager != null),
                    )
                )

                "startHosting" -> startHosting(once)
                "stopHosting" -> stopHosting { once.success(null) }
                "join" -> join(call.argument<String>("ssid")!!, call.argument<String>("passphrase")!!, once)
                "leave" -> leave { once.success(null) }
                else -> once.notImplemented()
            }
        } catch (e: Exception) {
            Log.w(TAG, "${call.method} failed", e)
            once.error("NEARBY_WIFI", e.message ?: e.toString())
        }
    }

    /** Tears everything down, e.g. when the activity is destroyed. */
    fun release() {
        stopHosting {}
        leave {}
    }

    private fun channel(): WifiP2pManager.Channel {
        val manager = p2pManager ?: throw IllegalStateException("Wi-Fi Direct is not available")
        return p2pChannel ?: manager.initialize(context, Looper.getMainLooper()) {
            p2pChannel = null
        }.also { p2pChannel = it }
    }

    // ---------------------------------------------------------------------------------------------
    // Hosting
    // ---------------------------------------------------------------------------------------------

    @SuppressLint("MissingPermission") // Requested in Dart before Nearby starts.
    private fun startHosting(result: OnceResult) {
        hosted?.let {
            result.success(it)
            return
        }
        if (!hasWifiDirect) {
            result.error("UNSUPPORTED", "This device does not support Wi-Fi Direct")
            return
        }
        val manager = p2pManager!!
        val channel = channel()
        // A group left over from an interrupted transfer would make createGroup fail with BUSY.
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = createGroup(manager, channel, result, retried = false)
            override fun onFailure(reason: Int) = createGroup(manager, channel, result, retried = false)
        })
    }

    @SuppressLint("MissingPermission")
    private fun createGroup(manager: WifiP2pManager, channel: WifiP2pManager.Channel, result: OnceResult, retried: Boolean) {
        val listener = object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                awaitOwnGroup(manager, channel, System.currentTimeMillis() + GROUP_TIMEOUT_MS, result)
            }

            override fun onFailure(reason: Int) {
                if (reason == WifiP2pManager.BUSY && !retried) {
                    handler.postDelayed({ createGroup(manager, channel, result, retried = true) }, 1_000)
                } else {
                    result.error("CREATE_GROUP_FAILED", "Could not create the Wi-Fi Direct group (${p2pReason(reason)})")
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val config = WifiP2pConfig.Builder()
                .setNetworkName("DIRECT-${randomString(2)}-Glide")
                .setPassphrase(randomString(12))
                .setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_AUTO)
                .build()
            manager.createGroup(channel, config, listener)
        } else {
            // The system picks the name and passphrase; they are read back below.
            manager.createGroup(channel, listener)
        }
    }

    /** Waits until the group is formed with this device as owner, then reports its credentials. */
    @SuppressLint("MissingPermission")
    private fun awaitOwnGroup(manager: WifiP2pManager, channel: WifiP2pManager.Channel, deadline: Long, result: OnceResult) {
        manager.requestConnectionInfo(channel) { info: WifiP2pInfo? ->
            val ownerAddress = info?.groupOwnerAddress?.hostAddress
            if (info == null || !info.groupFormed || !info.isGroupOwner || ownerAddress == null) {
                retryOrFail(deadline, result, "The Wi-Fi Direct group did not come up") {
                    awaitOwnGroup(manager, channel, deadline, result)
                }
                return@requestConnectionInfo
            }
            manager.requestGroupInfo(channel) { group: WifiP2pGroup? ->
                val name = group?.networkName
                val passphrase = group?.passphrase
                if (name == null || passphrase == null) {
                    retryOrFail(deadline, result, "The Wi-Fi Direct group did not report its credentials") {
                        awaitOwnGroup(manager, channel, deadline, result)
                    }
                    return@requestGroupInfo
                }
                val network = mapOf<String, Any>("ssid" to name, "passphrase" to passphrase, "ip" to ownerAddress)
                hosted = network
                Log.i(TAG, "Hosting $name at $ownerAddress")
                result.success(network)
            }
        }
    }

    private fun stopHosting(done: () -> Unit) {
        if (hosted == null) {
            done()
            return
        }
        hosted = null
        removeGroup(done)
    }

    // ---------------------------------------------------------------------------------------------
    // Joining
    // ---------------------------------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun join(ssid: String, passphrase: String, result: OnceResult) {
        if (hosted != null) {
            result.error("BUSY", "Already hosting a Wi-Fi Direct group")
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !hasWifiDirect) {
            joinLegacy(ssid, passphrase, result)
            return
        }
        val manager = p2pManager!!
        val channel = channel()
        val config = WifiP2pConfig.Builder()
            .setNetworkName(ssid)
            .setPassphrase(passphrase)
            .build()
        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                joinedAsP2pClient = true
                awaitJoined(manager, channel, System.currentTimeMillis() + JOIN_TIMEOUT_MS, result)
            }

            override fun onFailure(reason: Int) {
                result.error("CONNECT_FAILED", "Could not join $ssid (${p2pReason(reason)})")
            }
        })
    }

    private fun awaitJoined(manager: WifiP2pManager, channel: WifiP2pManager.Channel, deadline: Long, result: OnceResult) {
        manager.requestConnectionInfo(channel) { info: WifiP2pInfo? ->
            if (info != null && info.groupFormed && !info.isGroupOwner && info.groupOwnerAddress != null) {
                Log.i(TAG, "Joined the group of ${info.groupOwnerAddress.hostAddress}")
                result.success(null)
            } else {
                retryOrFail(deadline, result, "Timed out joining the Wi-Fi Direct group") {
                    awaitJoined(manager, channel, deadline, result)
                }
            }
        }
    }

    /** Before Android 10 a group can only be joined by name as a regular access point. */
    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    private fun joinLegacy(ssid: String, passphrase: String, result: OnceResult) {
        val manager = wifiManager
        if (manager == null) {
            result.error("UNSUPPORTED", "Wi-Fi is not available")
            return
        }
        if (!manager.isWifiEnabled) {
            manager.isWifiEnabled = true
        }
        val config = WifiConfiguration().apply {
            SSID = "\"$ssid\""
            preSharedKey = "\"$passphrase\""
        }
        val networkId = manager.addNetwork(config)
        if (networkId == -1) {
            result.error("CONNECT_FAILED", "Could not add the network $ssid")
            return
        }
        legacyNetworkId = networkId
        manager.disconnect()
        manager.enableNetwork(networkId, true)
        manager.reconnect()
        awaitLegacyJoined(manager, ssid, System.currentTimeMillis() + JOIN_TIMEOUT_MS, result)
    }

    @Suppress("DEPRECATION")
    private fun awaitLegacyJoined(manager: WifiManager, ssid: String, deadline: Long, result: OnceResult) {
        val info = manager.connectionInfo
        if (info != null && info.ssid == "\"$ssid\"" && info.ipAddress != 0) {
            result.success(null)
            return
        }
        retryOrFail(deadline, result, "Timed out joining $ssid") {
            awaitLegacyJoined(manager, ssid, deadline, result)
        }
    }

    @Suppress("DEPRECATION")
    private fun leave(done: () -> Unit) {
        legacyNetworkId?.let { networkId ->
            legacyNetworkId = null
            wifiManager?.let {
                it.disableNetwork(networkId)
                it.removeNetwork(networkId)
                // Back to the user's saved networks.
                it.reconnect()
            }
        }
        if (!joinedAsP2pClient) {
            done()
            return
        }
        joinedAsP2pClient = false
        p2pManager?.cancelConnect(channel(), null)
        removeGroup(done)
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    /** Leaves the current group: tears it down as owner, disconnects as client. */
    private fun removeGroup(done: () -> Unit) {
        val manager = p2pManager
        if (manager == null) {
            done()
            return
        }
        manager.removeGroup(channel(), object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.i(TAG, "Left the Wi-Fi Direct group")
                done()
            }

            override fun onFailure(reason: Int) {
                // Usually "no group": already gone, which is the goal.
                Log.i(TAG, "removeGroup: ${p2pReason(reason)}")
                done()
            }
        })
    }

    private fun retryOrFail(deadline: Long, result: OnceResult, message: String, retry: () -> Unit) {
        if (System.currentTimeMillis() > deadline) {
            result.error("TIMEOUT", message)
        } else {
            handler.postDelayed(retry, POLL_INTERVAL_MS)
        }
    }

    private fun p2pReason(reason: Int): String = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED -> "Wi-Fi Direct is not supported"
        WifiP2pManager.BUSY -> "Wi-Fi Direct is busy"
        WifiP2pManager.ERROR -> "internal error, is Wi-Fi turned on?"
        else -> "error $reason"
    }

    private fun randomString(length: Int): String {
        val alphabet = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        val random = SecureRandom()
        return (1..length).map { alphabet[random.nextInt(alphabet.length)] }.joinToString("")
    }
}

/** A [MethodChannel.Result] that ignores everything after the first reply. */
private class OnceResult(private val result: MethodChannel.Result) {
    private var replied = false

    fun success(value: Any?) {
        if (!replied) {
            replied = true
            result.success(value)
        }
    }

    fun error(code: String, message: String) {
        if (!replied) {
            replied = true
            result.error(code, message, null)
        }
    }

    fun notImplemented() {
        if (!replied) {
            replied = true
            result.notImplemented()
        }
    }
}
