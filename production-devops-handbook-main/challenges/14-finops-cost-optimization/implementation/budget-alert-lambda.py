#!/usr/bin/env python3
"""
AWS Budget Alert Lambda Function
Monitors AWS budgets and sends alerts when thresholds are exceeded
"""

import json
import boto3
import os
from datetime import datetime

# Initialize clients
budgets = boto3.client('budgets')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
ACCOUNT_ID = os.environ.get('AWS_ACCOUNT_ID')

def lambda_handler(event, context):
    """Main Lambda handler"""
    
    # Get all budgets
    response = budgets.describe_budgets(AccountId=ACCOUNT_ID)
    budgets_list = response.get('Budgets', [])
    
    alerts = []
    
    for budget in budgets_list:
        budget_name = budget['BudgetName']
        budget_limit = float(budget['BudgetLimit']['Amount'])
        
        # Get actual spend
        actual_spend = float(budget.get('CalculatedSpend', {}).get('ActualSpend', {}).get('Amount', 0))
        forecasted_spend = float(budget.get('CalculatedSpend', {}).get('ForecastedSpend', {}).get('Amount', 0))
        
        # Calculate percentages
        actual_percentage = (actual_spend / budget_limit) * 100 if budget_limit > 0 else 0
        forecast_percentage = (forecasted_spend / budget_limit) * 100 if budget_limit > 0 else 0
        
        # Check thresholds
        alert_level = None
        if actual_percentage >= 100:
            alert_level = 'CRITICAL'
        elif actual_percentage >= 90:
            alert_level = 'HIGH'
        elif actual_percentage >= 80:
            alert_level = 'MEDIUM'
        elif forecast_percentage >= 100:
            alert_level = 'WARNING'
        
        if alert_level:
            alert = {
                'budget_name': budget_name,
                'budget_limit': budget_limit,
                'actual_spend': actual_spend,
                'forecasted_spend': forecasted_spend,
                'actual_percentage': actual_percentage,
                'forecast_percentage': forecast_percentage,
                'alert_level': alert_level,
                'timestamp': datetime.now().isoformat()
            }
            alerts.append(alert)
            
            # Send SNS notification
            send_alert(alert)
            
            # Publish CloudWatch metric
            publish_metric(budget_name, actual_percentage)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'alerts_triggered': len(alerts),
            'alerts': alerts
        })
    }

def send_alert(alert):
    """Send alert via SNS"""
    subject = f"[{alert['alert_level']}] Budget Alert: {alert['budget_name']}"
    
    message = f"""
Budget Alert - {alert['alert_level']}

Budget: {alert['budget_name']}
Budget Limit: ${alert['budget_limit']:,.2f}
Actual Spend: ${alert['actual_spend']:,.2f} ({alert['actual_percentage']:.1f}%)
Forecasted Spend: ${alert['forecasted_spend']:,.2f} ({alert['forecast_percentage']:.1f}%)

Time: {alert['timestamp']}

Action Required: Review spending and implement cost optimization measures.
    """.strip()
    
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        print(f"✅ Alert sent for {alert['budget_name']}")
    except Exception as e:
        print(f"❌ Failed to send alert: {e}")

def publish_metric(budget_name, percentage):
    """Publish budget percentage to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='FinOps/Budgets',
            MetricData=[
                {
                    'MetricName': 'BudgetUtilization',
                    'Dimensions': [
                        {
                            'Name': 'BudgetName',
                            'Value': budget_name
                        }
                    ],
                    'Value': percentage,
                    'Unit': 'Percent',
                    'Timestamp': datetime.now()
                }
            ]
        )
    except Exception as e:
        print(f"Failed to publish metric: {e}")

# CloudFormation template for deployment
CLOUDFORMATION_TEMPLATE = """
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Budget Alert Lambda Function'

Parameters:
  AccountId:
    Type: String
    Description: AWS Account ID

Resources:
  BudgetAlertTopic:
    Type: AWS::SNS::Topic
    Properties:
      DisplayName: Budget Alerts
      Subscription:
        - Endpoint: devops@example.com
          Protocol: email

  BudgetAlertFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: budget-alert-monitor
      Runtime: python3.11
      Handler: index.lambda_handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Environment:
        Variables:
          SNS_TOPIC_ARN: !Ref BudgetAlertTopic
          AWS_ACCOUNT_ID: !Ref AccountId
      Code:
        ZipFile: |
          # Lambda function code (inline)

  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Policies:
        - PolicyName: BudgetAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - budgets:DescribeBudgets
                  - budgets:ViewBudget
                Resource: '*'
              - Effect: Allow
                Action:
                  - sns:Publish
                Resource: !Ref BudgetAlertTopic
              - Effect: Allow
                Action:
                  - cloudwatch:PutMetricData
                Resource: '*'

  ScheduledRule:
    Type: AWS::Events::Rule
    Properties:
      Description: Trigger budget check every 6 hours
      ScheduleExpression: rate(6 hours)
      State: ENABLED
      Targets:
        - Arn: !GetAtt BudgetAlertFunction.Arn
          Id: BudgetAlertTarget

  PermissionForEventsToInvokeLambda:
    Type: AWS::Lambda::Permission
    Properties:
      FunctionName: !Ref BudgetAlertFunction
      Action: lambda:InvokeFunction
      Principal: events.amazonaws.com
      SourceArn: !GetAtt ScheduledRule.Arn

Outputs:
  SNSTopicArn:
    Description: SNS Topic ARN for budget alerts
    Value: !Ref BudgetAlertTopic
  LambdaFunctionArn:
    Description: Lambda Function ARN
    Value: !GetAtt BudgetAlertFunction.Arn
"""

if __name__ == '__main__':
    # Test locally
    test_event = {}
    test_context = {}
    
    result = lambda_handler(test_event, test_context)
    print(json.dumps(result, indent=2))
