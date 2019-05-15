# Changelog
All notable changes to this project will be documented in this file.

## [1.7.35] - 2018-12-18
### Added
- Example

### Changed
- Example

### Removed
- Example

## [1.7.87] - 2018-12-18
### Added
- Added ignore local errors array 

## [1.7.86] - 2018-5-14
### Added
- Dont raise on i/o error for unicorn reading. 
- Change resque logger to info only. 
- Disabled apm start message settings

## [1.7.43] - 2018-12-31
### Added
- Ability to choose which app instance to launch in hallway
- Support for launching an app that's in hallway:
- verify_with_navbar
- select_instance

### Changed
- authenticate_connect_app_request

## [1.7.48] - 2019-1-7
### Added
- JavaScript files required to wrap application.js manifest for Hallway Integration


## [1.7.57] - 2019-1-29
### Changed
- Updated Hallway JS wrapper to redirect 401s from AJAX requests to login page


## [1.7.8] - 2019-03-14
### Added
- Cache Busting api on the app instance

### Changed
- initialize_app error status code, 400 changed to 500

## [1.7.81] - 2019-05-15
### Changed
- Updated migrations to have a specific version tag on them for rails 5