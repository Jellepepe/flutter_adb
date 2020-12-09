package dev.byme.adb;

import androidx.annotation.NonNull;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.EventChannel.StreamHandler;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.util.PathUtils;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

/** AdbPlugin */
public class AdbPlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel channel;
  private EventChannel outputChannel;
  private Context context;

  private Map<Object, EventChannel.EventSink> listeners = new HashMap<>();
  private final Consumer<String> readCallback = (String read) -> {
    for(Map.Entry<Object, EventChannel.EventSink> entry : listeners.entrySet()) {
      entry.getValue().success(read);
    }
  };

  

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getFlutterEngine().getDartExecutor(), "dev.byme.adb");
    outputChannel = new EventChannel(flutterPluginBinding.getFlutterEngine().getDartExecutor(), "dev.byme.adb/shellStream");
    context = flutterPluginBinding.getApplicationContext();
    channel.setMethodCallHandler(this);
    outputChannel.setStreamHandler(this);
  }

  // This static function is optional and equivalent to onAttachedToEngine. It supports the old
  // pre-Flutter-1.12 Android projects. You are encouraged to continue supporting
  // plugin registration via this function while apps migrate to use the new Android APIs
  // post-flutter-1.12 via https://flutter.dev/go/android-project-migration.
  //
  // It is encouraged to share logic between onAttachedToEngine and registerWith to keep
  // them functionally equivalent. Only one of onAttachedToEngine or registerWith will be called
  // depending on the user's project. onAttachedToEngine or registerWith must both be defined
  // in the same class.
  public static void registerWith(Registrar registrar) {
    AdbPlugin plugin = new AdbPlugin();
    final MethodChannel channel = new MethodChannel(registrar.messenger(), "dev.byme.adb");
    channel.setMethodCallHandler(plugin);

    final EventChannel outputChannel = new EventChannel(registrar.messenger(), "dev.byme.adb/shellStream");
    outputChannel.setStreamHandler(plugin);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (call.method.equals("getPlatformVersion")) {
      result.success("Android " + android.os.Build.VERSION.RELEASE);
    } else if (call.method.equals("attemptAdb")) {
      String command = call.argument("command");
      String adbResult = attemptAdb(command);
      result.success("trying adb command:\n" + command + "\nresult:\n" + adbResult);
    } else {
      result.notImplemented();
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }

  @Override
  public void onListen(Object listener, EventChannel.EventSink eventSink) {
    listeners.put(listener, new MainThreadEventSink(eventSink));
  }
    
  @Override
  public void onCancel(Object listener) {
    listeners.remove(listener);
  }

  public String attemptAdb(String command) {
    System.out.println("trying adb command: " + command);
    String returnString = "Successful";
    AdbThread adbThread = new AdbThread(command);
    Thread thread = new Thread(adbThread);
    thread.start();
    try {
      thread.join();
      return adbThread.getResult();
    } catch (InterruptedException e) {
      return "external error: " + e;
    }
    
  }

  public class AdbThread implements Runnable {
    private volatile String returnString;
    private final String command;
    AdbThread(String command) {
      this.command = command;
    }

    @Override
    public void run() {
      try {
        System.out.println("Creating connection");
        AdbManager selfAdb = AdbManager.initInstance(context.getFilesDir(), "10.0.2.2", 5557, readCallback);
        //selfAdb.executeCmd("pm grant " + BuildConfig.APPLICATION_ID + " android.permission.READ_LOGS");
        System.out.println("Executing command 1");
        selfAdb.executeCmd(this.command + "1");
        System.out.println("Executing command 2");
        selfAdb.executeCmd(this.command + "2");
        System.out.println("Disconnecting");
        selfAdb.disconnect();
      } catch (Exception e) {
        returnString = "internal error: " + e;
        System.out.println("internal error: " + e);
      }
    }

    public String getResult() {
      return returnString;
    }
  }

  private static class MainThreadEventSink implements EventChannel.EventSink {
    private EventChannel.EventSink eventSink;
    private Handler handler;

    MainThreadEventSink(EventChannel.EventSink eventSink) {
      this.eventSink = eventSink;
      handler = new Handler(Looper.getMainLooper());
    }

    @Override
    public void success(final Object o) {
      handler.post(new Runnable() {
        @Override
        public void run() {
          eventSink.success(o);
        }
      });
    }

    @Override
    public void error(final String s, final String s1, final Object o) {
      handler.post(new Runnable() {
        @Override
        public void run() {
          eventSink.error(s, s1, o);
        }
      });
    }

    @Override
    public void endOfStream() {
      handler.post(new Runnable() {
        @Override
        public void run() {
          eventSink.endOfStream();
        }
      });
    }
}
}
