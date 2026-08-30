# T8410X 低遅延ストリーミング

Eufy IndoorCam E220 (T8410X) + Thingino 上で Raptor を使い、~55ms のWebRTC映像配信を実現する設定一式。

## クイックスタート

1. PCで [Releases](../../releases) から `raptor-t31-t8410x.tar.gz` をダウンロード
2. カメラに転送（scp または SDカード経由）
   ```sh
   scp raptor-t31-t8410x.tar.gz root@<camera_ip>:/tmp/
   ```
3. カメラ上で展開してインストール:
   ```sh
   cd /tmp
   # BusyBox の tar は -z 非対応なので gunzip でパイプする
   gunzip -c raptor-t31-t8410x.tar.gz | tar x
   sh local-install.sh
   ```
4. ブラウザで `http://<camera_ip>/webrtc` を開く

> 注意: Thingino の tar は BusyBox 版なので `tar xzf` は使えません。
> `gunzip -c <file>.tar.gz | tar x` または `zcat <file>.tar.gz | tar x` を使ってください。

## 遅延性能

| 方式 | 遅延 |
|------|------|
| Thingino デフォルト (prudynt + RTSP + VLC) | ~600ms |
| Raptor + RTSP + ffplay (nobuffer) | ~150ms |
| **Raptor + WebRTC (ブラウザ)** | **~55ms** |

## ファイル構成

```
t8410x/
├── config/raptor.conf         # 低遅延設定
├── deploy/local-install.sh    # カメラ上で実行するインストーラー
├── deploy/start-raptor.sh     # カメラ上のinitスクリプト
└── README.md                  # この文書
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

カメラ上で実行:

```sh
/etc/init.d/S31raptor stop
rm /etc/init.d/S31raptor
chmod +x /etc/init.d/S95prudynt
/etc/init.d/S95prudynt start
```
