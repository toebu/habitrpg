scoring = require './scoring'
helpers = require './helpers'
_ = require 'underscore'
moment = require 'moment'
derby = require 'derby'

module.exports.view = (view) ->
  view.fn 'taskClasses', (type, completed, value, repeat) ->
    #TODO figure out how to just pass in the task model, so i can access all these properties from one object
    classes = type

    # show as completed if completed (naturally) or not required for today
    if completed or (repeat and repeat[helpers.dayMapping[moment().day()]]==false)
      classes += " completed"
    else
      classes += " uncompleted"

    if value < -20
      classes += ' color-worst'
    else if value < -10
      classes += ' color-worse'
    else if value < -1
      classes += ' color-bad'
    else if value < 1
      classes += ' color-neutral'
    else if value < 5
      classes += ' color-good'
    else if value < 10
      classes += ' color-better'
    else
      classes += ' color-best'
    return classes

module.exports.app = (appExports, model) ->
  user = model.at('_user')

  user.on 'set', 'tasks.*.completed', (i, completed, previous, isLocal, passed) ->
    return if passed? && passed.cron # Don't do this stuff on cron
    direction = () ->
      return 'up' if completed==true and previous == false
      return 'down' if completed==false and previous == true
      throw new Error("Direction neither 'up' nor 'down' on checkbox set.")

    # Score the user based on todo task
    task = user.at("tasks.#{i}")
    scoring.score(model, i, direction())

  appExports.addTask = (e, el, next) ->
    type = $(el).attr('data-task-type')
    list = model.at "_user.#{type}List"
    newModel = model.at('_new' + type.charAt(0).toUpperCase() + type.slice(1))
    text = newModel.get()
    # Don't add a blank task; 20/02/13 Added a check for undefined value, more at issue #463 -lancemanfv
    if /^(\s)*$/.test(text) || text == undefined
      console.error "Task text entered was an empty string."
      return

    newModel.set ''
    id = derby.uuid()
    switch type

      when 'habit'
        list.unshift {id: id, type: type, text: text, notes: '', value: 0, up: true, down: true}

      when 'reward'
        list.unshift {id: id, type: type, text: text, notes: '', value: 20 }

      when 'daily'
        list.unshift {id: id, type: type, text: text, notes: '', value: 0, repeat:{su:true,m:true,t:true,w:true,th:true,f:true,s:true}, completed: false }

      when 'todo'
        list.unshift {id: id, type: type, text: text, notes: '', value: 0, completed: false }


  appExports.del = (e, el) ->
    # Derby extends model.at to support creation from DOM nodes
    task = model.at(e.target)
    id = task.get('id')

    history = task.get('history')
    if history and history.length>2
      # prevent delete-and-recreate hack on red tasks
      if task.get('value') < 0
        result = confirm("Are you sure? Deleting this task will hurt you (to prevent deleting, then re-creating red tasks).")
        if result != true
          return # Cancel. Don't delete, don't hurt user
        else
          task.set('type','habit') # hack to make sure it hits HP, instead of performing "undo checkbox"
          scoring.score(model, id, direction:'down')

        # prevent accidently deleting long-standing tasks
      else
        result = confirm("Are you sure you want to delete this task?")
        return if result != true

    $('[rel=tooltip]').tooltip('hide')
    task.remove()


  appExports.clearCompleted = (e, el) ->
    todos = model.get('_user.todoList')
    removed = false
    _.each model.get('_user.todoList'), (task) ->
      if task.completed
        removed = true
        todos.splice(todos.indexOf(task), 1)
    if removed
      user.set('_user.todoList', todos)

  appExports.toggleDay = (e, el) ->
    task = model.at(e.target)
    if /active/.test($(el).attr('class')) # previous state, not current
      task.set('repeat.' + $(el).attr('data-day'), false)
    else
      task.set('repeat.' + $(el).attr('data-day'), true)

  appExports.toggleTaskEdit = (e, el) ->
    hideId = $(el).attr('data-hide-id')
    toggleId = $(el).attr('data-toggle-id')
    $(document.getElementById(hideId)).hide()
    $(document.getElementById(toggleId)).toggle()

  appExports.toggleChart = (e, el) ->
    hideSelector = $(el).attr('data-hide-id')
    chartSelector = $(el).attr('data-toggle-id')
    historyPath = $(el).attr('data-history-path')
    $(document.getElementById(hideSelector)).hide()
    $(document.getElementById(chartSelector)).toggle()

    matrix = [['Date', 'Score']]
    for obj in model.get(historyPath)
      date = +new Date(obj.date)
      readableDate = moment(date).format('MM/DD')
      matrix.push [ readableDate, obj.value ]
    data = google.visualization.arrayToDataTable matrix

    options = {
      title: 'History'
      #TODO use current background color: $(el).css('background-color), but convert to hex (see http://goo.gl/ql5pR)
      backgroundColor: 'whiteSmoke'
    }

    chart = new google.visualization.LineChart(document.getElementById( chartSelector ))
    chart.draw(data, options)

  appExports.changeContext = (e, el) ->
    # Get the data from the element
    targetSelector = $(el).attr('data-target')
    newContext = $(el).attr('data-context')
    newActiveNav = $(el).parent('li')

    # If the clicked nav is already active, do nothing
    if newActiveNav.hasClass('active')
      return

    # Find the old active nav and context
    oldActiveNav = $(el).closest('ul').find('> .active')
    oldContext = oldActiveNav.find('a').attr('data-context')

    # Set the new active nav
    oldActiveNav.removeClass('active')
    newActiveNav.addClass('active')

    # Set the new context on the target
    target = $(targetSelector)
    target.removeClass(oldContext)
    target.addClass(newContext)

  appExports.score = (e, el, next) ->
    direction = $(el).attr('data-direction')
    direction = 'up' if direction == 'true/'
    direction = 'down' if direction == 'false/'
    task = model.at $(el).parents('li')[0]
    scoring.score(model, task.get('id'), direction)

  appExports.tasksToggleAdvanced = (e, el) ->
    $(el).next('.advanced').toggle()

  appExports.tasksSaveAndClose = ->
    # When they update their notes, re-establish tooltip & popover
    $('[rel=tooltip]').tooltip()
    $('[rel=popover]').popover()

  appExports.tasksSetPriority = (e, el) ->
    dataId = $(el).parent('[data-id]').attr('data-id')
    #"_user.tasks.#{dataId}"
    model.at(e.target).set 'priority', $(el).attr('data-priority')