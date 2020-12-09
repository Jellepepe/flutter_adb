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




public class AdbManager {
    private static AdbManager instance;
    private AdbCrypto adbCrypto;
    private Socket socket;
    private AdbConnection adbConnection;
    private AdbStream shellStream;
    private boolean isConnected = false;

    public static AdbManager initInstance(File fileDir, String hostname, int port) throws InterruptedException, NoSuchAlgorithmException, IOException {
        if (instance!=null){
            instance.disconnect();
        }
        instance = new AdbManager(fileDir, hostname, port);
        return instance;
    }

    public static AdbManager getInstance() throws InterruptedException, NoSuchAlgorithmException, IOException {
        return instance;
    }

    private AdbManager(File fileDir, String hostname, int port) throws IOException, NoSuchAlgorithmException, InterruptedException {
        adbCrypto = setupCrypto(fileDir, "public.key", "private.key");
        socket = new Socket();
        connect(hostname, port);
    }

    private void connect(String address, int port) throws IOException, InterruptedException {
        socket.connect(new InetSocketAddress(address, port), 5000);
        adbConnection = AdbConnection.create(socket, adbCrypto);
        adbConnection.connect();
        shellStream = adbConnection.open("shell:");
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