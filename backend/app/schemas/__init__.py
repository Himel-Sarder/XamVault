"""Pydantic request/response schemas.

Response schemas are separated by audience (see docs/api.md §4): a field that must not
reach a given role is *absent from that role's class*, so a leak requires adding a field
rather than forgetting to remove one.
"""
