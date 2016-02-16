# Plusone

Counts ``+1`` in github issues and shows you how many in a badge.

[![Issue #1](http://plusone-demo.herokuapp.com/count.svg?repo=ukd1/plusone&issue=1&sig=fcc82e36f38a2246df3732679c145b8061a282738d07192b22bda48b67114d04029cb2386f330f89639a2028c8fe021ef09985aa72a80b946589c8a1875e744e)](https://github.com/ukd1/plusone/issues/1) - example for this repo: go try and +1 it!

## Notes / deployment

This is has no specs yet, sorry. It requires redis. Click to deploy on Heroku:

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

p.s. due to the way Heroku Redis works, it will likely fail the first time it boots until Redis is provisioned. Wait a minute or two and it should be good to go. If you get stuck ``heroku restart -a <your-app-name>``.

## Setup

Go to your app and enter your username and password. Then fill in the form, it will give you setup instructions from there - you have to setup the webhook (once per repo) then the badge (once per issue).