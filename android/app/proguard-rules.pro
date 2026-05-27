-keep class com.example.entropy_vpn.EntropyHevTunnel {
    *;
}

-keep class com.example.entropy_vpn.EntropyHevTunnel$Companion {
    *;
}

-keep class io.nekohasekai.libbox.** {
    *;
}

-keep class com.example.entropy_vpn.EntropyVpnService {
    *;
}

-keep class com.example.entropy_vpn.MainActivity {
    *;
}

-keepclasseswithmembernames class * {
    native <methods>;
}
