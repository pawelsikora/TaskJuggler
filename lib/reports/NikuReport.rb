#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = NikuReport.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'AppConfig'
require 'reports/ReportBase'

class TaskJuggler

  class NikuProject

    attr_reader :name, :id, :tasks, :resources

    def initialize(id, name)
      @id = id
      @name = name
      @tasks = []
      @resources = {}
    end

  end

  class NikuResource

    attr_reader :id
    attr_accessor :sum

    def initialize(id)
      @id = id
      @sum = 0.0
    end

  end

  # The Niku report can be used to export resource allocation data for certain
  # task groups in the Niku XOG format. This file can be read by the Clarity
  # enterprise resource management software from Computer Associates.
  # Since I don't think this is a use case for many users, the implementation
  # is somewhat of a hack. The report relies on 3 custom attributes that the
  # user has to define in the project.
  # Resources must be tagged with a ClarityRID and Tasks must have a
  # ClarityPID and a ClarityPName.
  # This file format works for our Clarity installation. I have no idea if it
  # is even portable to other Clarity installations.
  class NikuReport < ReportBase

    def initialize(report)
      super(report)

      # A Hash to store NikuProject objects by id
      @projects = {}

      # A Hash to map ClarityRID to Resource
      @resources = {}

      # Resources total effort during the report period hashed by ClarityId
      @resourcesTotalEffort = {}
    end

    def generateIntermediateFormat
      super

      @scenarioIdx = a('scenarios')[0]

      computeResourceTotals
      collectProjects
      computeProjectAllocations
    end

    def to_html
      tableBlock = XMLElement.new('div', 'class' => 'tj_table_block')
      tableBlock << (tableFrame =
                     XMLElement.new('div', 'class' => 'tj_table_frame'))

      # Headline box
      if a('headline')
        tableFrame << (div = XMLElement.new('div',
                                            'class' => 'tj_table_headline'))
        div << a('headline').to_html
      end

      tableFrame << (table = XMLElement.new('table', 'class' => 'tj_table'))

      # Table Header
      table << (tr = XMLElement.new('tr', 'class' => 'tabline'))
      tr << htmlTabCell('Resource\Project', true, 'center')
      @projects.each_key do |projectId|
        tr << htmlTabCell(projectId, true, 'center')
      end
      tr << htmlTabCell('Total', true, 'center')

      @resourcesTotalEffort.each_key do |resourceId|
        table << (tr = XMLElement.new('tr', 'class' => 'tabline'))
        tr << htmlTabCell("#{@resources[resourceId].name} (#{resourceId})",
                          true, 'left')

        @projects.each_key do |projectId|
          tr << htmlTabCell(format("%.2f", sum(projectId, resourceId)))
        end

        tr << htmlTabCell(format("%.2f", resourceTotal(resourceId)), true)
      end

      # Project totals
      table << (tr = XMLElement.new('tr', 'class' => 'tabline'))
      tr << htmlTabCell('Total', 'true', 'left')
      @projects.each_key do |projectId|
        tr << htmlTabCell(format("%.2f", projectTotal(projectId)), true, 'right')
      end
      tr << htmlTabCell(format("%.2f", total()), true, 'right')

      tableBlock
    end

    def to_niku
      xml = XMLDocument.new
      xml << XMLComment.new(<<"EOT"
Generated by #{AppConfig.softwareName} v#{AppConfig.version} on #{TjTime.now}
For more information about #{AppConfig.softwareName} see #{AppConfig.contact}.
Project: #{@project['name']}
Date:    #{@project['now']}
EOT
                           )
      xml << (nikuDataBus =
              XMLElement.new('NikuDataBus',
                             'xmlns:xsi' =>
                             'http://www.w3.org/2001/XMLSchema-instance',
                             'xsi:noNamespaceSchemaLocation' =>
                             '../xsd/nikuxog_project.xsd'))
      nikuDataBus << XMLElement.new('Header', 'action' => 'write',
                                    'externalSource' => 'NIKU',
                                    'objectType' => 'project',
                                    'version' => '7.5.0')
      nikuDataBus << (projects = XMLElement.new('Projects'))

      timeFormat = '%Y-%m-%dT%H:%M:%S'
      @projects.each_value do |prj|
        # Don't include projects with 0 allocations
        next if projectTotal(prj.id) <= 0.0

        projects << (project =
                     XMLElement.new('Project',
                                    'name' => prj.name,
                                    'projectID' => prj.id))
        project << (resources = XMLElement.new('Resources'))
        prj.resources.each_value do |res|
          resources << (resource =
                        XMLElement.new('Resource',
                                       'resourceID' => res.id,
                                       'defaultAllocation' => '0'))
          resource << (allocCurve = XMLElement.new('AllocCurve'))
          value = sum(prj.id, res.id)
          allocCurve << (XMLElement.new('Segment',
                                        'start' =>
                                        a('start').to_s(timeFormat),
                                        'finish' =>
                                        (a('end') - 1).to_s(timeFormat),
                                        'sum' => value > 0.0 ? value.to_s : ''))
        end

        # The custom information section usually contains Clarity installation
        # specific parts. They are identical for each project section, so we
        # mis-use the title attribute to insert them as an XML blob.
        project << XMLBlob.new(a('title')) unless a('title').empty?
      end

      xml.to_s
    end

  private

    def sum(projectId, resourceId)
      project = @projects[projectId]
      return 0.0 unless project

      resource = project.resources[resourceId]
      return 0.0 unless resource && @resourcesTotalEffort[resourceId]

      resource.sum / @resourcesTotalEffort[resourceId]
    end

    def resourceTotal(resourceId)
      total = 0.0
      @projects.each_key do |projectId|
        total += sum(projectId, resourceId)
      end
      total
    end

    def projectTotal(projectId)
      total = 0.0
      @resources.each_key do |resourceId|
        total += sum(projectId, resourceId)
      end
      total
    end

    def total
      total = 0.0
      @projects.each_key do |projectId|
        @resources.each_key do |resourceId|
          total += sum(projectId, resourceId)
        end
      end
      total
    end

    def htmlTabCell(text, headerCell = false, align = 'right')
      td = XMLElement.new('td', 'class' => headerCell ? 'tabhead' : 'taskcell1')
      td << XMLNamedText.new(text, 'div',
                             'class' => headerCell ? 'headercelldiv' : 'celldiv',
                             'style' => "text-align:#{align}")
      td
    end


    # The report must contain percent values for the allocation of the
    # resources. A value of 1.0 means 100%. The resource is fully allocated
    # for the whole report period. To compute the percentage later on, we
    # first have to compute the maximum possible allocation.
    def computeResourceTotals
      # Prepare the resource list.
      resourceList = PropertyList.new(@project.resources)
      resourceList.setSorting(@report.get('sortResources'))
      resourceList = filterResourceList(resourceList, nil,
                                        @report.get('hideResource'),
                                        @report.get('rollupResource'))

      resourceList.each do |resource|
        # We only care about leaf resources that have the custom attribute
        # 'ClarityRID' set.
        next if !resource.leaf? ||
                (resourceId = resource.get('ClarityRID')).nil? ||
                resourceId.empty?

        # Prepare a template for the Query we will use to get all the data.
        queryAttrs = { 'project' => @project,
                       'property' => resource,
                       'scopeProperty' => nil,
                       'scenarioIdx' => @scenarioIdx,
                       'loadUnit' => a('loadUnit'),
                       'numberFormat' => a('numberFormat'),
                       'timeFormat' => a('timeFormat'),
                       'currencyFormat' => a('currencyFormat'),
                       'start' => a('start'), 'end' => a('end'),
                       'costAccount' => a('costAccount'),
                       'revenueAccount' => a('revenueAccount') }

        query = Query.new(queryAttrs)

        # First get the allocated effort.
        query.attributeId = 'effort'
        query.process
        total = query.to_num

        # Then add the still available effort.
        query.attributeId = 'freework'
        query.process
        total += query.to_num

        next if total <= 0.0

        @resources[resourceId] = resource

        # This is the maximum possible work of this resource in the report
        # period.
        @resourcesTotalEffort[resourceId] = total
      end

      # Make sure that we have at least one Resource with a ClarityRID.
      if @resourcesTotalEffort.empty?
        raise TjException.new,
          'No resources with the custom attribute ClarityRID were found!'
      end
    end

    # Search the Task list for the various ClarityPIDs and create a new Task
    # list for each ClarityPID.
    def collectProjects
      # Prepare the task list.
      taskList = PropertyList.new(@project.tasks)
      taskList.setSorting(@report.get('sortTasks'))
      taskList = filterTaskList(taskList, nil, @report.get('hideTask'),
                                @report.get('rollupTask'))


      taskList.each do |task|
        # We only care about tasks that are leaf tasks and have resource
        # allocations.
        next unless task.leaf? ||
                    task['assignedresources', @scenarioIdx].empty?

        id = task.get('ClarityPID')
        # Ignore tasks without a ClarityPID attribute.
        next if id.nil?
        if id.empty?
          raise "ClarityPID of task #{task.fullId} may not be empty"
        end

        name = task.get('ClarityPName')
        if name.nil?
          raise "ClarityPName of task #{task.fullId} has not been set!"
        end
        if name.empty?
          raise "ClarityPName of task #{task.fullId} may not be empty!"
        end

        if (project = @projects[id]).nil?
          # We don't have a record for the Clarity project yet, so we create a
          # new NikuProject object.
          project = NikuProject.new(id, name)
          # And store it in the project list hashed by the ClarityPID.
          @projects[id] = project
        else
          # Due to a design flaw in the Niku file format, Clarity projects are
          # identified by a name and an ID. We have to check that those pairs
          # are always the same.
          if (fTask = project.tasks.first).get('ClarityPName') != name
            raise TjException.new,
              "Task #{task.fullId} and task #{fTask.fullId} " +
              "have same ClarityPID (#{id}) but different ClarityPName " +
              "(#{name}/#{fTask.get('ClarityPName')})"
          end
        end
        # Append the Task to the task list of the Clarity project.
        project.tasks << task
      end

      if @projects.empty?
        raise TjException.new,
          'No tasks with the custom attributes ClarityPID and ClarityPName ' +
          'were found!'
      end
    end

    # Compute the total effort each Resource is allocated to the Task objects
    # that have the same ClarityPID.
    def computeProjectAllocations
      @projects.each_value do |project|
        project.tasks.each do |task|
          task['assignedresources', @scenarioIdx].each do |resource|
            # Only consider resources that are in the filtered resource list.
            next unless @resources[resource.get('ClarityRID')]

            # Prepare a template for the Query we will use to get all the data.
            queryAttrs = { 'project' => @project,
                           'property' => task,
                           'scopeProperty' => resource,
                           'scenarioIdx' => @scenarioIdx,
                           'loadUnit' => a('loadUnit'),
                           'numberFormat' => a('numberFormat'),
                           'timeFormat' => a('timeFormat'),
                           'currencyFormat' => a('currencyFormat'),
                           'start' => a('start'), 'end' => a('end'),
                           'costAccount' => a('costAccount'),
                           'revenueAccount' => a('revenueAccount') }

            query = Query.new(queryAttrs)
            query.attributeId = 'effort'
            query.process
            work = query.to_num

            # If the resource was not actually working on this task during the
            # report period, we don't create a record for it.
            next if work <= 0.0

            resourceId = resource.get('ClarityRID')
            if (resourceRecord = project.resources[resourceId]).nil?
              # If we don't already have a NikuResource object for the
              # Resource, we create a new one.
              resourceRecord = NikuResource.new(resourceId)
              # Store the new NikuResource in the resource list of the
              # NikuProject record.
              project.resources[resourceId] = resourceRecord
            end
            resourceRecord.sum += query.to_num
          end
        end
      end
    end

  end

end

