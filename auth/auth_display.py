#!/usr/bin/env python3
"""
SpotiPi Auth QR Display
========================
Fullscreen pygame window showing Spotify OAuth QR code.
Receives the auth URL as argv[1].
Exits when /tmp/spotipi_auth_done appears (written by spotify_auth.py callback).
"""

import sys
import time
from pathlib import Path

import pygame
import qrcode

DONE_FLAG = Path("/tmp/spotipi_auth_done")
BG = (0, 0, 0)
FG = (255, 255, 255)
GRAY = (179, 179, 179)
GREEN = (29, 185, 84)


def make_qr_surface(url: str, size: int) -> pygame.Surface:
    qr = qrcode.QRCode(version=1,
                       error_correction=qrcode.constants.ERROR_CORRECT_M,
                       box_size=10, border=4)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="white", back_color="black")
    tmp = Path("/tmp/spotipi_auth_qr.png")
    img.save(tmp)
    surf = pygame.image.load(str(tmp))
    return pygame.transform.scale(surf, (size, size))


def main():
    if len(sys.argv) < 2:
        print("Usage: auth_display.py <auth_url>")
        sys.exit(1)

    auth_url = sys.argv[1]
    DONE_FLAG.unlink(missing_ok=True)

    pygame.init()
    info = pygame.display.Info()
    W, H = info.current_w or 1920, info.current_h or 1080
    screen = pygame.display.set_mode((W, H), pygame.FULLSCREEN | pygame.NOFRAME)
    pygame.display.set_caption("SpotiPi Auth")
    pygame.mouse.set_visible(False)

    font_title = pygame.font.SysFont("sans-serif", 40, bold=True)
    font_body = pygame.font.SysFont("sans-serif", 24)
    font_url = pygame.font.SysFont("monospace", 14)

    qr_size = min(W, H) // 3
    qr_surf = make_qr_surface(auth_url, qr_size)

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

        title = font_title.render("用手機掃描授權 Spotify", True, GREEN)
        screen.blit(title, ((W - title.get_width()) // 2, 30))

        qr_x = (W - qr_size) // 2
        qr_y = (H - qr_size) // 2 - 30
        screen.blit(qr_surf, (qr_x, qr_y))

        hint = font_body.render("或在手機瀏覽器開啟以下網址：", True, GRAY)
        screen.blit(hint, ((W - hint.get_width()) // 2, qr_y + qr_size + 20))

        # Show truncated URL so it fits
        max_url_chars = W // 8
        url_display = auth_url if len(auth_url) <= max_url_chars else auth_url[:max_url_chars - 3] + "..."
        url_surf = font_url.render(url_display, True, (120, 120, 120))
        screen.blit(url_surf, ((W - url_surf.get_width()) // 2, qr_y + qr_size + 60))

        pygame.display.flip()
        clock.tick(10)

    pygame.quit()


if __name__ == "__main__":
    main()
