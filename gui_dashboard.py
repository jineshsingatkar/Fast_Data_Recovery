#!/usr/bin/env python3
# Fast Data Recovery - GUI Dashboard (cross-platform)
# Provides four tile-style actions similar to the requested design:
# - Deleted Recovery
# - Complete Recovery (guided)
# - Lost Partition Recovery
# - Digital Media Recovery
#
# The GUI launches external console tools (TestDisk/PhotoRec) where available.
# On Windows, place testdisk_win.exe and photorec_win.exe beside this script or in PATH.
# On Linux, install 'testdisk' and 'photorec' packages.

import os
import sys
import subprocess
import shutil
import platform
import PySimpleGUI as sg

SCRIPT_DIR = os.path.abspath(os.path.dirname(__file__))

# Utility

def which(names):
    if isinstance(names, str):
        names = [names]
    for n in names:
        p = shutil.which(n)
        if p:
            return p
        # also check local folder
        cand = os.path.join(SCRIPT_DIR, n)
        if os.path.exists(cand):
            return cand
    return None

IS_WINDOWS = platform.system() == 'Windows'
TESTDISK_CMD = which(['testdisk_win.exe', 'testdisk'])
PHOTOREC_CMD = which(['photorec_win.exe', 'photorec'])
SMARTCTL_CMD = which(['smartctl.exe', 'smartctl'])

# Actions

def run_smart():
    if not SMARTCTL_CMD:
        sg.popup_error('smartctl not found. Install smartmontools.', title='Missing tool')
        return
    dev = sg.popup_get_text('Enter disk device (Windows: \\.\\PhysicalDrive0, Linux: /dev/sda):', title='SMART Target')
    if not dev:
        return
    try:
        # Launch in a new console window where possible
        if IS_WINDOWS:
            subprocess.Popen(['powershell', '-NoProfile', '-WindowStyle', 'Normal', SMARTCTL_CMD, '-a', '-d', 'auto', dev])
        else:
            subprocess.Popen(['x-terminal-emulator', '-e', SMARTCTL_CMD, '-a', '-d', 'auto', dev])
    except Exception as e:
        sg.popup_error(f'Failed to run smartctl: {e}')


def launch_testdisk(target: str | None = None):
    if not TESTDISK_CMD:
        sg.popup_error('TestDisk not found. Install testdisk or place testdisk_win.exe here.', title='Missing tool')
        return
    args = [TESTDISK_CMD]
    if target:
        args.append(target)
    try:
        if IS_WINDOWS:
            subprocess.Popen(args)
        else:
            # Prefer to run within a terminal
            term = shutil.which('x-terminal-emulator') or shutil.which('gnome-terminal') or shutil.which('konsole') or shutil.which('xterm')
            if term:
                subprocess.Popen([term, '-e'] + args)
            else:
                subprocess.Popen(args)
    except Exception as e:
        sg.popup_error(f'Failed to start TestDisk: {e}')


def launch_photorec(target: str | None = None):
    if not PHOTOREC_CMD:
        sg.popup_error('PhotoRec not found. Install photorec or place photorec_win.exe here.', title='Missing tool')
        return
    args = [PHOTOREC_CMD]
    if target:
        args.append(target)
    try:
        if IS_WINDOWS:
            subprocess.Popen(args)
        else:
            term = shutil.which('x-terminal-emulator') or shutil.which('gnome-terminal') or shutil.which('konsole') or shutil.which('xterm')
            if term:
                subprocess.Popen([term, '-e'] + args)
            else:
                subprocess.Popen(args)
    except Exception as e:
        sg.popup_error(f'Failed to start PhotoRec: {e}')


# GUI Layout
sg.theme('SystemDefault')

TILE_SIZE = (25, 3)

deleted_btn = sg.Button('Deleted\nRecovery', size=TILE_SIZE, key='DELETED', button_color=('white', '#079bc9'))
complete_btn = sg.Button('Complete\nRecovery', size=TILE_SIZE, key='COMPLETE', button_color=('white', '#079bc9'))
lostpart_btn = sg.Button('Lost Partition\nRecovery', size=TILE_SIZE, key='LOSTPART', button_color=('white', '#079bc9'))
media_btn = sg.Button('Digital Media\nRecovery', size=TILE_SIZE, key='MEDIA', button_color=('white', '#079bc9'))

menu_row = [
    [deleted_btn, complete_btn, lostpart_btn, media_btn],
]

controls = [
    [sg.Button('SMART Check', key='SMART'), sg.Button('Exit')]
]

layout = [
    [sg.Text('Fast Data Recovery - GUI Dashboard', font=('Segoe UI', 14))],
    [sg.Column(menu_row, element_justification='center')],
    [sg.HorizontalSeparator()],
    [sg.Column(controls, element_justification='left')],
    [sg.Text('Tips: Use SMART to assess health. Image first if failing. Work on clones/images.', text_color='orange')]
]

window = sg.Window('Fast Data Recovery', layout, finalize=True)

while True:
    event, values = window.read()
    if event == sg.WINDOW_CLOSED or event == 'Exit':
        break
    elif event == 'SMART':
        run_smart()
    elif event in ('DELETED', 'MEDIA'):
        # For media, suggest filtering to media types inside PhotoRec
        launch_photorec()
    elif event == 'LOSTPART':
        launch_testdisk()
    elif event == 'COMPLETE':
        # Guided dialog
        choice = sg.popup_yes_no('Recommended: 1) SMART check, 2) If failing, create ddrescue image on Linux, 3) Run TestDisk/PhotoRec on the image.\n\nRun SMART now?', title='Complete Recovery')
        if choice == 'Yes':
            run_smart()
        else:
            # Offer to open README
            readme = os.path.join(SCRIPT_DIR, 'README.md')
            if os.path.exists(readme):
                try:
                    if IS_WINDOWS:
                        os.startfile(readme)  # type: ignore[attr-defined]
                    else:
                        subprocess.Popen(['xdg-open', readme])
                except Exception:
                    pass

window.close()

