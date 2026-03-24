#!/usr/bin/env python3
"""
SpotiPi WiFi QR Display
=======================
Shows a fullscreen pygame window with a QR code for connecting to the AP.
Exits when a signal file appears (written by wifi_setup.py after success).
"""

import sys
import time
from pathlib import Path

import pygame
import qrcode

sys.path.insert(0, str(Path(__file__).parent.parent))
import config

DONE_FLAG = Path("/tmp/spotipi_wifi_done")
BG = (0, 0, 0)
FG = (255, 255, 255)
GRAY = (179, 179, 179)

PORTAL_URL = f"http://{config.AP_IP}"


def make_qr_surface(data: str, size: int) -> pygame.Surface:
    qr = qrcode.QRCode(version=1, error_correction=qrcode.constants.ERROR_CORRECT_M,
                       box_size=10, border=4)
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="white", back_color="black")
    tmp = Path("/tmp/spotipi_wifi_qr.png")
    img.save(tmp)
    surf = pygame.image.load(str(tmp))
    return pygame.transform.scale(surf, (size, size))


def main():
    pygame.init()
    info = pygame.display.Info()
    W, H = info.current_w or 1920, info.current_h or 1080
    screen = pygame.display.set_mode((W, H), pygame.FULLSCREEN | pygame.NOFRAME)
    pygame.display.set_caption("SpotiPi WiFi Setup")
    pygame.mouse.set_visible(False)

    font_title = pygame.font.SysFont("sans-serif", 40, bold=True)
    font_body = pygame.font.SysFont("sans-serif", 28)
    font_small = pygame.font.SysFont("sans-serif", 20)

    qr_size = min(W, H) // 3
    qr_surf = make_qr_surface(PORTAL_URL, qr_size)

    clock = pygame.time.Clock()
    running = True

    while running:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                running = False
            elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
                running = False

        if DONE_FLAG.exists():
            running = False

        screen.fill(BG)

        # Title
        t = font_title.render("連接 SpotiPi-Setup WiFi", True, FG)
        screen.blit(t, ((W - t.get_width()) // 2, 40))

        # QR
        qr_x = (W - qr_size) // 2
        qr_y = (H - qr_size) // 2 - 40
        screen.blit(qr_surf, (qr_x, qr_y))

        # Subtitle
        s1 = font_body.render(f"SSID: {config.AP_SSID}  /  Password: {config.AP_PASSWORD}", True, GRAY)
        screen.blit(s1, ((W - s1.get_width()) // 2, qr_y + qr_size + 20))

        s2 = font_small.render(f"連上後開瀏覽器 → {PORTAL_URL}", True, GRAY)
        screen.blit(s2, ((W - s2.get_width()) // 2, qr_y + qr_size + 60))

        ip_text = font_small.render(f"AP IP: {config.AP_IP}", True, (100, 100, 100))
        screen.blit(ip_text, ((W - ip_text.get_width()) // 2, H - 50))

        pygame.display.flip()
        clock.tick(10)

    pygame.quit()


if __name__ == "__main__":
    main()
