package dev.byme.adb;

import com.cgutman.adblib.AdbBase64;
import com.cgutman.adblib.AdbConnection;
import com.cgutman.adblib.AdbCrypto;
import com.cgutman.adblib.AdbStream;

import org.apache.commons.codec.binary.Base64;

import java.io.File;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.security.NoSuchAlgorithmException;
import java.util.function.Consumer;




public class AdbManager {
    private static AdbManager instance;
    private AdbCrypto adbCrypto;
    private Socket socket;
    private AdbConnection adbConnection;
    private AdbStream shellStream;
    private boolean isConnected = false;
    private Consumer<String> readCallBack;

    private Thread readThread = new Thread(new Runnable() {
        @Override
        public void run() {
            while(shellStream != null && !shellStream.isClosed())
                    try {
                        String shellOutputString = new String(shellStream.read(), "US-ASCII");
                        System.out.print("Out: " + shellOutputString);
                        readCallBack.accept(shellOutputString);
                    } catch (Exception e) {
                        System.out.println("Error: "+ e.toString());
                    }
        }
    });

    public static AdbManager initInstance(File fileDir, String hostname, int port, Consumer<String> readCallback) throws InterruptedException, NoSuchAlgorithmException, IOException {
        if (instance!=null){
            instance.disconnect();
        }
        instance = new AdbManager(fileDir, hostname, port, readCallback);
        return instance;
    }

    public static AdbManager getInstance() throws InterruptedException, NoSuchAlgorithmException, IOException {
        return instance;
    }

    private AdbManager(File fileDir, String hostname, int port, Consumer<String> readCallback) throws IOException, NoSuchAlgorithmException, InterruptedException {
        this.readCallBack = readCallback;
        adbCrypto = setupCrypto(fileDir, "public.key", "private.key");
        socket = new Socket();
        connect(hostname, port);
    }

    private void connect(String address, int port) throws IOException, InterruptedException {
        isConnected = true;
        socket.connect(new InetSocketAddress(address, port), 5000);
        adbConnection = AdbConnection.create(socket, adbCrypto);
        adbConnection.connect();
        shellStream = adbConnection.open("shell:");
        readThread.start();
    }

    public void disconnect() throws IOException {
        shellStream.close();
        adbConnection.close();
        socket.close();
        instance = null;
    }

    private static AdbBase64 getBase64Impl() {
        return data -> Base64.encodeBase64String(data);
    }

    private AdbCrypto setupCrypto(File fileDir, String pubKeyFile, String privKeyFile) throws NoSuchAlgorithmException, IOException {
        File publicKey = new File(fileDir, pubKeyFile);
        File privateKey = new File(fileDir, privKeyFile);
        AdbCrypto c = null;

        if (publicKey.exists() && privateKey.exists())
        {
            try {
                c = AdbCrypto.loadAdbKeyPair(getBase64Impl(), privateKey, publicKey);
            } catch (Exception e) {
                c = null;
            }
        }

        if (c == null)
        {
            c = AdbCrypto.generateAdbKeyPair(getBase64Impl());
            c.saveAdbKeyPair(privateKey, publicKey);
        }

        return c;
    }

    public void executeCmd(String cmd) throws IOException, InterruptedException {
        shellStream.write(cmd + "\n");
    }

    public void executeShellCmds(String[] cmds) throws IOException, InterruptedException{
        for (String cmd : cmds){
            shellStream.write(cmd + "\n");
        }
    }

}