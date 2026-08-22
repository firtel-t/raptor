# T8410X 低遅延ストリーミング

Eufy IndoorCam E220 (T8410X) + Thingino 上で Raptor を使い、~55ms のWebRTC映像配信を実現する設定一式。

## クイックスタート

1. [Releases](../../releases) から `raptor-t31-t8410x.tar.gz` をダウンロード
2. デプロイ:
   ```bash
   tar xzf raptor-t31-t8410x.tar.gz
   ./deploy.sh 192.168.1.xxx
   ```
3. ブラウザで `http://<camera_ip>/webrtc` を開く

## 遅延性能

| 方式 | 遅延 |
|------|------|
| Thingino デフォルト (prudynt + RTSP + VLC) | ~600ms |
| Raptor + RTSP + ffplay (nobuffer) | ~150ms |
| **Raptor + WebRTC (ブラウザ)** | **~55ms** |

## ファイル構成

```
t8410x/
├── config/raptor.conf      # 低遅延設定
├── deploy/deploy.sh        # ワンコマンドデプロイ
├── deploy/start-raptor.sh  # カメラ上のinitスクリプト
└── README.md               # この文書
```

## 受信側コマンド

```bash
# ffplay (低遅延)
ffplay -fflags nobuffer -flags low_delay -framedrop \
  -analyzeduration 0 -probesize 32 \
  -rtsp_transport udp rtsp://<camera_ip>/stream0

# mpv
mpv --no-cache --untimed --profile=low-latency rtsp://<camera_ip>/stream0
```

## 設定チューニング

`t8410x/config/raptor.conf` を編集:

- **帯域不足**: `bitrate = 2000` に下げる or 解像度 1280x720
- **パケロス多い**: `gop = 10` に短縮
- **遅延計測**: カメラ上で `ringdump main -l`、PC上で `rlatency rtsp://<ip>/stream0`

## 元に戻す

```bash
ssh root@<camera_ip>
/etc/init.d/S31raptor stop
rm /etc/init.d/S31raptor
chmod +x /etc/init.d/S95prudynt
/etc/init.d/S95prudynt start
```
