"""The player's side of the spoiler boundary.

Everything in this package reads only ``investigation.json`` (plus the player's own
``session.json``). The single exception is :func:`mystery.investigate.verdict.reveal`,
which opens ``truth.json`` and refuses to do so until the case has been concluded.
"""
